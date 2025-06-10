import SwiftUI
import JavaScriptCore

func gatherTree(context: JSContext, cb: () -> Void) -> AnyView {
    var collectedViews: [AnyView] = []

    let hBlock: @convention(block) (JSValue, JSValue, JSValue, JSValue, JSValue) -> Void = { arg0, arg1, arg2, arg3, arg4 in
        let jsArguments = [arg1, arg2, arg3, arg4].filter { $0.isObject }

        var props: [String: JSValue] = [:]
        var childrenFunc: () -> AnyView = {
            AnyView(EmptyView())
        }
        for jsArgument in jsArguments {
            if jsArgument.isFunction {
                childrenFunc = {
                    gatherTree(context: context) {
                        jsArgument.call(withArguments: [])
                    }
                }
            } else {
                let newProps = unwrapJSObject(jsArgument)
                props.merge(newProps) { (_, new) in new }
            }
        }
        
        var view: any View
        if arg0.isFunction {
            // Another component
            view = JSView(arg0, props: props)
            collectedViews.append(AnyView(view))
            return
        }
    
        switch (arg0.toString()) {
        case "VStack":
            view = VStack(content:childrenFunc)
        case "Button":
            let action = props["action"]!
            let actionFunc = {
                _ = action.call(withArguments: [])
            }
            props.removeValue(forKey: "action")
            view = Button(action: actionFunc, label:childrenFunc)
        case "Text":
            let content = props["content"]?.toString() ?? ""
            props.removeValue(forKey: "content")
            view = Text(content)
        default:
            print("unknown native element ", arg0)
            return;
        }
        view = applyViewModifiers(to: view, from: props)
        collectedViews.append(AnyView(view))
    }

    let prevHBlock = context.objectForKeyedSubscript("h")
    context.setObject(unsafeBitCast(hBlock, to: AnyObject.self),
                      forKeyedSubscript: "h" as NSString)

    // Execute callback, that will invoke hBlocks above
    cb()
    
    // Reset h() to previous
    context.setObject(prevHBlock, forKeyedSubscript: "h" as NSString)

    // Consider:
    // if collectedViews.count == 0 {
    //     return AnyView(EmptyView())
    // }
    // if collectedViews.count == 1 {
    //     return AnyView(collectedViews.first)
    // }
    return AnyView(ForEach(0..<collectedViews.count, id: \.self) { index in
        collectedViews[index]
    })

}

struct JSView: View {
    var renderFn: JSValue
    // TODO: should we put in JSValues here directly? How do they equate?
    var props: [String: Any]
    @State var state: [String: Any]? = nil
    
    init(_ renderFn: JSValue, props: [String: Any] = [:]) {
        self.renderFn = renderFn
        self.props = props
        if self._state.wrappedValue == nil {
            // JSView lifecycle is shorter than @State vars in SwiftUI. Only initialize to
            // initialState when nil. TODO: do this nicer.
            let initialState = unwrapJSObject(renderFn.objectForKeyedSubscript("initialState")!)
            self._state = State(initialValue: initialState)
        }
    }
    
    var componentName: String {
        // TODO: fix
        renderFn.objectForKeyedSubscript("name").toString()
    }
    
    func setState(state: JSValue) {
        self.state = self.state!.merging(unwrapJSObject(state)) { (_, new) in new }
    }

    var body: some View {
        let context = renderFn.context!;
        let jsProps = JSValue(object: props, in: context)!
        let jsState = JSValue(object: state, in: context)!
        let setStateCallback: @convention(block) (JSValue) -> Void = { newState in
            self.setState(state: newState)
        }
        let jsSetState = JSValue(object: setStateCallback, in: context)!

        return gatherTree(context: context) {
            renderFn.call(withArguments: [jsProps, jsState, jsSetState])
        }
    }
}


func applyViewModifiers(to view: some View, from props: [String: JSValue]) -> AnyView {
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


struct JSRoot: View {
    let context = setupJSContext()
    let jsCode = loadJSCode(named:"app")

    var body: some View {
        print("evaluating jsCode \(jsCode.count)b")
        context.evaluateScript(jsCode)
        let appComponent = context.objectForKeyedSubscript("App")!
        return JSView(appComponent)
    }
}


@main
struct JSApp: App {
    var body: some Scene {
        WindowGroup {
            JSRoot()
        }
    }
}
