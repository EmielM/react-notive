import SwiftUI
import JavaScriptCore

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

struct Node: CustomStringConvertible, Equatable {
    let type: String
    let props: [String: JSValue]
    let children: [Node]
    
    let renderFn: JSValue?
    let initialState: [String: JSValue]?

    init(jsValue: JSValue) {
        self.type = jsValue.forProperty("type").toString()!
        self.props = unwrapJSObject(jsValue.forProperty("props"))
        self.children = unwrapJSArray(jsValue.forProperty("children")).map({ Node(jsValue: $0) })
        
        self.renderFn = jsValue.forProperty("renderFn") ?? nil;
        self.initialState = jsValue.forProperty("initialState").flatMap({ unwrapJSObject($0) })
    }
    
    var description: String {
        return "<\(type) \(props.keys) />"
    }
}


// MARK: - JSComponentModel

class JSComponentModel: ObservableObject {
    @Published var renderFn: JSValue
    @Published var props: [String: JSValue]
    @Published var children: [Node]

    @Published var state: [String: JSValue]

    let context: JSContext
    var subModels: [String: JSComponentModel] = [:]

    init(context: JSContext, renderFn: JSValue, props: [String: JSValue], children: [Node], state: [String: JSValue]) {
        self.context = context;
        self.renderFn = renderFn;
        self.props = props;
        self.children = children;
        self.state = state;
    }
        
    func setState(state: JSValue) {
        self.state = unwrapJSObject(state)
    }

    func render() -> AnyView {
        let jsProps = JSValue(object: props, in: context)!
        let jsState = JSValue(object: state, in: context)!
        
        let setStateCallback: @convention(block) (JSValue) -> Void = { [weak self] newState in
            self?.setState(state: newState)
        }
        let jsSetState = JSValue(object: setStateCallback, in: context)!

        let result = renderFn.call(withArguments: [jsProps, jsState, jsSetState])!
        
        let node = Node(jsValue: result)
        return renderNode(node, atPath: [])
    }

    func renderNode(_ node: Node, atPath: [String]) -> AnyView {
        print("renderNode ", node) // TODO: triggered twice somehow
        
        if node.type == "Component" {
            let subModelKey = atPath.joined(separator: " ")
            if let existingModel = subModels[subModelKey] {
                if (existingModel.renderFn == node.renderFn && existingModel.props == node.props && existingModel.children == node.children) {
                    print("reuse existing model @ ", existingModel.renderFn)
                    return AnyView(JSComponentView(model: existingModel))
                }
                print("update model @ ", subModelKey)
            } else {
                print("new model @ ", subModelKey)
            }
            let newModel = JSComponentModel(
                context: context,
                renderFn: node.renderFn!,
                props: node.props,
                children: node.children,
                state: node.initialState!
            )
            subModels[subModelKey] = newModel;
            return AnyView(JSComponentView(model: newModel))
        }
        
        @ViewBuilder
        func renderChildren() -> some View {
            ForEach(node.children.indices, id: \.self) { index in
                self.renderNode(node.children[index], atPath: atPath + [String(index)])
            }
        }

        var view: any View
        switch node.type {
        case "List":
            view = List(content:renderChildren)
        case "VStack":
            view = VStack(content:renderChildren)
        case "Text":
            view = Text(node.props["content"]!.toString())
        case "Button":
            view = Button(
                action: {
                    withAnimation {
                        _ = node.props["action"]!.call(withArguments: [])
                    }
                },
                label: renderChildren
            )
        default:
            view = EmptyView()
        }
        
        view = applyModifiers(to: view, from: node.props)
        return AnyView(view)
    }
}

func applyModifiers(to view: some View, from props: [String: JSValue]) -> AnyView {
    var modifiedView: AnyView = AnyView(view)

    for (key, value) in props {
        switch key {
        case "transition":
            if let name = value.toString(), let transition = makeTransition(named: name) {
                modifiedView = AnyView(modifiedView.transition(transition))
            }

        case "opacity":
            if let number = value.toNumber() {
                modifiedView = AnyView(modifiedView.opacity(number.doubleValue))
            }

        case "foregroundColor":
            if let colorName = value.toString(), let color = makeColor(named: colorName) {
                modifiedView = AnyView(modifiedView.foregroundColor(color))
            }
            
        case "background":
            if let colorName = value.toString(), let color = makeColor(named: colorName) {
                modifiedView = AnyView(modifiedView.background(color))
            }

        case "frame":
            if let dict = value.toObject() as? [String: JSValue] {
                let width = dict["width"]?.toNumber().flatMap(CGFloat.init)
                let height = dict["height"]?.toNumber().flatMap(CGFloat.init)
                modifiedView = AnyView(modifiedView.frame(width: width, height: height))
            }

        case "padding":
            if value.isNumber {
                modifiedView = AnyView(modifiedView.padding(value.toNumber().doubleValue))
            } else if let dict = value.toObject() as? [String: JSValue] {
                let top = dict["top"]?.toNumber()?.doubleValue ?? 0
                let bottom = dict["bottom"]?.toNumber()?.doubleValue ?? 0
                let leading = dict["leading"]?.toNumber()?.doubleValue ?? 0
                let trailing = dict["trailing"]?.toNumber()?.doubleValue ?? 0
                modifiedView = AnyView(modifiedView.padding(.init(top: top, leading: leading, bottom: bottom, trailing: trailing)))
            } else {
                modifiedView = AnyView(modifiedView.padding())
            }

        default:
            print("unknown modifier \(key)")
            continue
        }
    }

    return modifiedView
}

func makeTransition(named name: String) -> AnyTransition? {
    switch name {
    case "scale": return .scale
    case "opacity": return .opacity
    case "slide": return .slide
    case "moveLeading": return .move(edge: .leading)
    case "moveTrailing": return .move(edge: .trailing)
    case "moveTop": return .move(edge: .top)
    case "moveBottom": return .move(edge: .bottom)
    default: return nil
    }
}

func makeColor(named name: String) -> Color? {
    switch name.lowercased() {
    case "red": return .red
    case "blue": return .blue
    case "green": return .green
    case "black": return .black
    case "white": return .white
    case "gray": return .gray
    default: return nil
    }
}


// MARK: - JSComponentView

struct JSComponentView: View {
    @ObservedObject var model: JSComponentModel
    var body: some View {
        return model.render()
    }
}

// MARK: - JSContext Setup

func setupContext() -> JSContext {
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
        let stack = exception.objectForKeyedSubscript("stack")?.toString() ?? "<no stack>"

        print("⚠️ JavaScript Error: \(message)")
        print("📍 Stack trace:\n\(stack)")
    }
    
    return context
}

// MARK: - Main SwiftUI App Entry
struct AppRootView: View {
    let context = setupContext()
    let jsCode = loadJSCode(named:"app")

    var body: some View {
        print("evaluating jsCode \(jsCode.count)b")
        context.evaluateScript(jsCode)
        let appFn = context.objectForKeyedSubscript("App")!
        return JSComponentView(model: JSComponentModel(
            context: context,
            renderFn: appFn,
            props: [:],
            children: [],
            state: [:]
        ))
    }
}

func loadJSCode(named fileName: String) -> String {
    let url = Bundle.main.url(forResource: fileName, withExtension: "js")!
    return try! String(contentsOf: url)
}

@main
struct YourApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
