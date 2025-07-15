import SwiftUI
import JavaScriptCore

public func setupJSContext() -> JSContext {
    let context = JSContext()!

    // Add `console.log` shim
    let consoleLog: @convention(block) (JSValue, JSValue, JSValue) -> Void = { arg0, arg1, arg2 in
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
    let console = JSValue(newObjectIn: context)!
    console.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
    context.setObject(console, forKeyedSubscript: "console" as NSString)

    // Add basic setTimeout implementation
    let setTimeout: @convention(block) (JSValue, Double) -> Void = { callback, delay in
        let delayInSeconds = delay / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delayInSeconds) {
            callback.call(withArguments: [])
        }
    }
    context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)

    context.exceptionHandler = { context, exception in
        guard let exception = exception else { return }

        let message = exception.toString() ?? "Unknown JS exception"
        // TODO: stack collection works badly
        let stack = exception.objectForKeyedSubscript("stack")?.toString() ?? "<no stack>"

        print("⚠️ JavaScript Error: \(message)")
        print("📍 Stack trace:\n\(stack)")
    }
    
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
