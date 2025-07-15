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
    
    // Allow subscript access in swift: props["label"]
    subscript(key: String) -> JSValue? {
        get { self.objectForKeyedSubscript(key) }
    }
    
    // Bunch of bridge() overloads to allow eazy unwrapping to a shape we want

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
            return jsVal.toObject().debugDescription
        } else {
            return jsVal.toString()
        }
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
        if let method = initDict["method"]?.toString() {
            request.httpMethod = method
        }
        if let headers: [String: JSValue] = initDict["headers"]?.bridge()  {
            for (key, value) in headers {
                request.setValue(value.toString(), forHTTPHeaderField: key)
            }
        }
        if let body = initDict["body"]?.toString() {
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
