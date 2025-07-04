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

func unwrapJSArray(_ jsArray: JSValue) -> [JSValue] {
    let length = jsArray.forProperty("length")!.toInt32()

    return (0..<length).map { index in
        jsArray.atIndex(Int(index))
    }
}

func unwrapJSObject(_ jsObject: JSValue) -> [String: JSValue] {
    guard jsObject.isObject,
          let context = jsObject.context,
          let keysValue = context.objectForKeyedSubscript("Object")
                               .objectForKeyedSubscript("keys")?
                               .call(withArguments: [jsObject]),
          let keys = keysValue.toArray() as? [String] else {
        return [:]
    }

    return Dictionary(uniqueKeysWithValues: keys.compactMap { key in
        jsObject.forProperty(key).map { (key, $0) }
    })
}

extension JSValue {
    var isFunction: Bool {
        guard self.isObject else {
            return false
        }
        
        var isFunction = self.context.objectForKeyedSubscript("_isFunction")!
        if isFunction.isUndefined {
            print("Injecting _isFunction!");
            self.context.evaluateScript("function _isFunction(value) { return typeof value === 'function'; }");
            isFunction = self.context.objectForKeyedSubscript("_isFunction")
        }

        return isFunction.call(withArguments:[self])!.toBool()
    }
}
