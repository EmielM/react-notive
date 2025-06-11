import SwiftUI
import JavaScriptCore

func gatherTree(context: JSContext, cb: () -> Void) -> AnyView {
    var collectedViews: [AnyView] = []

    // h("VStack", {some: "prop", propB: 123}, {more: "props"}, () => {
    //     h("Text", {color: 'white'}, "text")
    // })
    let hBlock: @convention(block) (JSValue, JSValue, JSValue, JSValue, JSValue, JSValue) -> Void = { arg0, arg1, arg2, arg3, arg4, arg5 in
        var props: [String: JSValue] = [:]
        var childrenFunc: () -> AnyView = {
            AnyView(EmptyView())
        }
        // Supporting 6 args is a bit arbitrary, no way to bind varargs to swift blocks easily
        for jsArgument in [arg1, arg2, arg3, arg4, arg5] {
            if jsArgument.isFunction {
                childrenFunc = {
                    gatherTree(context: context) {
                        jsArgument.call(withArguments: [])
                    }
                }
            } else if jsArgument.isString {
                // Treat strings as {content: "string"} prop
                props["content"] = jsArgument
            } else if jsArgument.isObject {
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
            let spacing = toCGFloat(props["spacing"])
            props.removeValue(forKey:"spacing")
            view = VStack(spacing:spacing,content:childrenFunc)
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
    var modifiedView: any View = view

    // Always apply props in the same order, as it matters in SwiftUI how things are applioed
    // - It does mean we're not as versatile from javascript
    // - Consider: using multi-props argument, support ordering here?

    if let paddingProp = props["padding"] {
        if paddingProp.isNull {
            modifiedView = modifiedView.padding()
        } else if paddingProp.isNumber {
            modifiedView = modifiedView.padding(toCGFloat(paddingProp) ?? 0)
        } else if paddingProp.isObject {
            let padding = unwrapJSObject(paddingProp)
            modifiedView = modifiedView.padding(EdgeInsets(
                top: padding["top"].flatMap { toCGFloat($0) } ?? 0,
                leading: padding["leading"].flatMap { toCGFloat($0) } ?? 0,
                bottom: padding["bottom"].flatMap { toCGFloat($0) } ?? 0,
                trailing: padding["trailing"].flatMap { toCGFloat($0) } ?? 0
            ))
        }
    }
    
    if let frameProp = props["frame"], frameProp.isObject {
        let frame = unwrapJSObject(frameProp)
        modifiedView = modifiedView.frame(
            width: frame["width"].flatMap { toCGFloat($0) },
            height: frame["height"].flatMap { toCGFloat($0) },
            alignment: .center
        ).frame(
            maxWidth: frame["maxWidth"].flatMap { toCGFloat($0) },
            maxHeight: frame["maxHeight"].flatMap { toCGFloat($0) }
        )
    }


    if let transitionProp = props["transition"]?.toString() {
        if let transition = makeTransition(named: transitionProp) {
            modifiedView = modifiedView.transition(transition)
        }
    }
    
    if let opacityProp = props["opacity"]?.toNumber() {
        modifiedView = modifiedView.opacity(opacityProp.doubleValue)
    }

    if let foregroundColorProp = props["foregroundColor"]?.toString() {
        if let color = makeColor(named: foregroundColorProp) {
            modifiedView = modifiedView.foregroundColor(color)
        }
    }

    if let backgroundProp = props["background"]?.toString() {
        if let color = makeColor(named: backgroundProp) {
            modifiedView = modifiedView.background(color)
        }
    }
    
    if let fontProp = props["font"]?.toString() {
        switch fontProp {
        case "largeTitle": modifiedView = modifiedView.font(.largeTitle)
        case "title": modifiedView = modifiedView.font(.title)
        case "headline": modifiedView = modifiedView.font(.headline)
        case "body": modifiedView = modifiedView.font(.body)
        default: break
        }
    }
    
    if let fontWeightProp = props["fontWeight"]?.toString() {
        switch fontWeightProp {
        case "semibold": modifiedView = modifiedView.fontWeight(.semibold)
        case "bold": modifiedView = modifiedView.fontWeight(.bold)
        case "regular": modifiedView = modifiedView.fontWeight(.regular)
        default: break
        }
    }

    if let cornerRadiusProp = props["cornerRadius"]?.toNumber() {
        modifiedView = modifiedView.cornerRadius(CGFloat(cornerRadiusProp.doubleValue))
    }

    return AnyView(modifiedView)
}

// Helper
func toCGFloat(_ value: JSValue?) -> CGFloat? {
    guard let number = value?.toNumber() else { return nil }
    let doubleValue = number.doubleValue
    if doubleValue == Double.infinity {
        return .infinity
    }
    return CGFloat(doubleValue)
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
            //NativeView()
        }
    }
}
