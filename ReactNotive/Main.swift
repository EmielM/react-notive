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

// Consider: make Hashable?
struct Node: CustomStringConvertible {
    let type: String
    let props: [String: JSValue]
    let children: [Node]

    init(jsValue: JSValue) {
        self.type = jsValue.forProperty("type").toString()!
        self.props = unwrapJSObject(jsValue.forProperty("props"))
        self.children = unwrapJSArray(jsValue.forProperty("children")).map({ Node(jsValue: $0) })
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
        return renderNode(node)
    }

    func renderNode(_ node: Node) -> AnyView {
        print("renderNode ", node) // TODO: triggered twice somehow

        switch node.type {
        case "Component":
            // TODO: reuse model based on path we're at (/key prop?)
            let model = JSComponentModel(
                context: context,
                renderFn: node.props["renderFn"]!,
                props: node.props,
                children: children,
                state: unwrapJSObject(node.props["initialState"]!)
            )
            return AnyView(JSComponentView(model: model))

        case "Text":
            let text = node.props["content"]!.toString()!
            return AnyView(Text(text))

        case "Button":
            return AnyView(Button(action: {
                node.props["action"]!.call(withArguments: [])
            }) {
                ForEach(node.children.indices, id: \.self) { index in
                    self.renderNode(node.children[index])
                }
            })

        case "VStack":
            return AnyView(VStack {
                ForEach(node.children.indices, id: \.self) { index in
                    self.renderNode(node.children[index])
                }
            })

        default:
            return AnyView(EmptyView())
        }
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
    let consoleLog: @convention(block) (JSValue) -> Void = { message in
        print("JavaScript log: \(message)")
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
