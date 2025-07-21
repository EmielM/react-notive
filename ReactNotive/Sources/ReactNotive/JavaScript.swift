import SwiftUI
import JavaScriptCore

public func setupJSContext() -> JSContext {
    let context = JSContext()!

    context.exceptionHandler = { context, exception in
        guard let exception = exception else { return }

        let message = exception.toString() ?? "Unknown JS exception"
        // TODO: stack collection works badly
        let stack = exception.objectForKeyedSubscript("stack")?.toString() ?? "<no stack>"

        print("⚠️ JavaScript Error: \(message)")
        print("📍 Stack trace:\n\(stack)")
    }
    
    let console = JSValue(newObjectIn: context)!
    console.setObject(consoleLogFunction, forKeyedSubscript: "log" as NSString)
    context.setObject(console, forKeyedSubscript: "console" as NSString)

    context.setObject(setTimeoutFunction, forKeyedSubscript: "setTimeout" as NSString)
    
    context.setObject(fetchFunction, forKeyedSubscript: "fetch" as NSString)
    context.setObject(controllerConstructor, forKeyedSubscript: "AbortController" as NSString)
    
    let registerApp: @convention(block) (JSValue) -> Void = { appComponent in
        // TODO: use the appComponent passed here (where to save?), instead of getting global.App
        print("registerApp? ", appComponent)
    }
    
    context.setObject(registerApp, forKeyedSubscript: "registerApp" as NSString)

    return context
}

public func loadJSCode(named fileName: String) -> String {
    let url = Bundle.main.url(forResource: fileName, withExtension: "js")!
    return try! String(contentsOf: url)
}

extension JSValue {
    // Missing in JavaScriptCore
    var isFunction: Bool {
        guard self.isObject else {
            return false
        }
        return self.isInstance(of: self.context.objectForKeyedSubscript("Function"))
    }
    
    /// Allow subscript access in swift: props["label"]
    /// - "undefined" will map to nil, allowing smoother chain operation
    subscript(key: String) -> JSValue? {
        get {
            guard let value = self.objectForKeyedSubscript(key), !value.isUndefined
            else {
                return nil
            }
            return value
        }
    }
    
    /// Call a JS function that returns a Promise, and await its resolution in Swift.
    func callAndAwait(withArguments arguments: [Any] = []) async throws -> JSValue {
        let context = self.context!

        return try await withCheckedThrowingContinuation { continuation in
            // Create resolve and reject callbacks
            let resolve: @convention(block) (JSValue) -> Void = { value in
                continuation.resume(returning: value)
            }

            let reject: @convention(block) (JSValue) -> Void = { error in
                let swiftError = NSError(
                    domain: "js",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: error.toString() ?? "JavaScript error"]
                )
                continuation.resume(throwing: swiftError)
            }

            // Convert blocks to JSValues
            let resolveFn = JSValue(object: resolve, in: context)!
            let rejectFn = JSValue(object: reject, in: context)!

            // Call the JS function, get a Promise
            guard let promise = self.call(withArguments: arguments) else {
                continuation.resume(throwing: NSError(domain: "js", code: 0, userInfo: [NSLocalizedDescriptionKey: "JS function call failed"]))
                return
            }
            
            // Attach .then and .catch directly on the returned Promise
            promise.invokeMethod("then", withArguments: [resolveFn])
            promise.invokeMethod("catch", withArguments: [rejectFn])
            
            // Register a cancellation handler
            Task {
                if Task.isCancelled {
                    print("callAndAwait CANCEL!!")
                    // Optional: reject the JS Promise manually if you expose a cancellation hook
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
    }

    
    // Bunch of bridge() overloads to allow eazy unwrapping to a shape we want

    func bridge() -> Bool? {
        guard self.isBoolean else {
            return nil
        }
        return self.toBool()
    }
    
    func bridge() -> String? {
        guard self.isString else {
            return nil
        }
        return self.toString()
    }
    
    func bridge() -> Int? {
        guard self.isNumber else {
            return nil
        }
        return Int(self.toInt32())
    }
    
    func bridge() -> Double? {
        guard self.isNumber else {
            return nil
        }
        return self.toDouble()
    }
    
    func bridge() -> [JSValue]? {
        guard self.isArray else {
            return nil
        }
        let length = self.forProperty("length")!.toInt32()
        return (0..<length).map { index in
            self.atIndex(Int(index))
        }
    }
    
    func bridge() -> [String: JSValue]? {
        guard self.isObject, !self.isNull else {
            return nil
        }
        
        let context = self.context!
        guard let keysValue = context.objectForKeyedSubscript("Object")
                                     .objectForKeyedSubscript("keys")?
                                     .call(withArguments: [self]),
              let keys = keysValue.toArray() as? [String]
        else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            self.forProperty(key).map { (key, $0) }
        })
    }
    
    func bridge() -> [String: Double]? {
        guard let object: [String: JSValue] = self.bridge()
        else {
            return nil
        }

        // Non-number values will be removed
        return object.compactMapValues { $0.isNumber ? $0.toDouble() : nil }
    }
    
    func bridge() -> (() -> Void)? {
        guard self.isFunction else {
            return nil
        }
        return {
            self.call(withArguments: [])
        }
    }

    func bridge() -> ((JSValue) -> JSValue)? {
        guard self.isFunction else {
            return nil
        }
        return { arg in
            self.call(withArguments: [arg])
        }
    }
    
    func bridge() -> ((JSValue) -> String)? {
        guard self.isFunction else {
            return nil
        }
        return { arg in
            // TODO: cannot check return type at time of bridge() call
            self.call(withArguments: [arg]).toString()!
        }
    }

}

extension JSContext {
    func makePromise(
        executor: @escaping (_ fulfill: JSValue, _ reject: JSValue) -> Void
    ) -> JSValue {
        let promiseCtor = objectForKeyedSubscript("Promise")!
        let wrapper: @convention(block) (JSValue, JSValue) -> Void = { fulfill, reject in
            executor(fulfill, reject)
        }
        let block = JSValue(object: wrapper, in: self)!
        return promiseCtor.construct(withArguments: [block])
    }

    func makeRejectedPromise(reason: String) -> JSValue {
        let promiseCtor = objectForKeyedSubscript("Promise")!
        return promiseCtor.invokeMethod("reject", withArguments: [reason])!
    }
}

let setTimeoutFunction: @convention(block) (JSValue, Double) -> Void = { callback, delay in
    // TODO: probably not allow this, to prevent weird side effects and prepare for multiple JS threads
    let delayInSeconds = delay / 1000.0
    DispatchQueue.main.asyncAfter(deadline: .now() + delayInSeconds) {
        callback.call(withArguments: [])
    }
}

let consoleLogFunction: @convention(block) (JSValue, JSValue, JSValue) -> Void = { arg0, arg1, arg2 in
    let args: [JSValue] = [arg0, arg1, arg2].filter { !$0.isUndefined }
    let descriptions = args.map { jsVal in
        if jsVal.isString {
            return jsVal.toString()! // "\"\(jsVal.toString()!)\""
        } else if jsVal.isBoolean {
            return jsVal.toBool() ? "true" : "false"
        } else if jsVal.isNumber {
            return "\(jsVal.toNumber()!)"
        } else if jsVal.isArray || jsVal.isObject {
            if let jsValObject = jsVal.toObject() as? NSObject {
                return jsValObject.debugDescription
            }
        }
        return jsVal.toString()
    }

    print("JS: ", descriptions.joined(separator: " "))
}

let fetchFunction: @convention(block) (JSValue, JSValue?) -> JSValue = { input, initOptions in
    guard let context = input.context,
          let urlString = input.toString(),
          let url = URL(string: urlString)
    else {
        return input.context!.makeRejectedPromise(reason: "Invalid URL")
    }

    var request = URLRequest(url: url)

    if let initDict: [String: JSValue] = initOptions?.bridge() {
        if let method: String = initDict["method"]?.bridge() {
            request.httpMethod = method
        }
        if let headers: [String: JSValue] = initDict["headers"]?.bridge()  {
            for (key, value) in headers {
                request.setValue(value.toString(), forHTTPHeaderField: key)
            }
        }
        if let body: String = initDict["body"]?.bridge() {
            request.httpBody = body.data(using: .utf8)
        }
    }

    return context.makePromise { fulfill, reject in
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, let http = response as? HTTPURLResponse else {
                reject.call(withArguments: [error?.localizedDescription ?? "Unknown error"])
                return
            }

            let resObj = JSValue(newObjectIn: context)!
            resObj.setObject(http.statusCode, forKeyedSubscript: "status" as NSString)
            resObj.setObject(http.statusCode >= 200 && http.statusCode < 300, forKeyedSubscript: "ok" as NSString)

            let headersObj = JSValue(newObjectIn: context)!
            for (key, value) in http.allHeaderFields {
                headersObj.setObject("\(value)", forKeyedSubscript: "\(key)" as NSString)
            }
            resObj.setObject(headersObj, forKeyedSubscript: "headers" as NSString)

            // .text()
            let textBlock: @convention(block) () -> JSValue = {
                JSValue(object: String(data: data, encoding: .utf8) ?? "", in: context)
            }
            resObj.setObject(textBlock, forKeyedSubscript: "text" as NSString)

            // .json()
            let jsonBlock: @convention(block) () -> JSValue = {
                let json = try? JSONSerialization.jsonObject(with: data)
                return JSValue(object: json, in: context)
            }
            resObj.setObject(jsonBlock, forKeyedSubscript: "json" as NSString)

            fulfill.call(withArguments: [resObj])
        }
        task.resume()
    }
}


class JSAbortSignal: NSObject, JSExport {
    var aborted = false
    private var listeners: [JSValue] = []

    func addEventListener(_ type: String, _ listener: JSValue) {
        guard type == "abort" else { return }
        listeners.append(listener)
    }

    func dispatchAbortEvent() {
        guard !aborted else { return }
        print("setting aborted to true!!")
        aborted = true
        for listener in listeners {
            listener.call(withArguments: [])
        }
    }
    
    @objc func throwIfAborted() {
        if aborted {
            let error = JSValue(newErrorFromMessage: "Aborted", in: JSContext.current())
            error?.setValue("AbortError", forProperty: "name")
            JSContext.current()?.exception = error
        }
    }
}

@objc protocol JSAbortControllerExport: JSExport {
    var signal: JSAbortSignal { get }
    func abort()
}

class JSAbortController: NSObject, JSAbortControllerExport {
    let signal = JSAbortSignal()

    func abort() {
        signal.dispatchAbortEvent()
    }
}

let controllerConstructor: @convention(block) () -> JSAbortController = {
    JSAbortController()
}
