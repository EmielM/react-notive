import SwiftUI
import JavaScriptCore

func renderNode(_ node: JSValue) -> AnyView {
    if !node.isObject || node.isNull {
        fatalError("renderNode not an object")
    }
    
    let type = node.objectForKeyedSubscript("type")!
    var props = unwrapJSObject(node.objectForKeyedSubscript("props"))
    
    if type.isFunction {
        // Another component
        return AnyView(JSView(type, props: props))
    }
    
    var childrenFunc: () -> AnyView = {
        AnyView(EmptyView())
    }
    
    let childrenProp = props["children"]
    if let childrenProp, childrenProp.isArray {
        // Multiple children
        let childrenArray = unwrapJSArray(childrenProp)
        childrenFunc = {
            return AnyView(ForEach(Array(childrenArray.enumerated()), id: \.offset) { index, childNode in
                return AnyView(renderNode(childNode))
            })
        }
        props.removeValue(forKey: "children")
    } else if let childrenProp, childrenProp.isObject {
        // Single child
        childrenFunc = {
            return AnyView(renderNode(childrenProp))
        }
        props.removeValue(forKey: "children")
    }
    
    var view: any View;
    switch (type.toString()) {
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
        let content = props["children"]?.toString() ?? ""
        props.removeValue(forKey: "content")
        view = Text(content)
    default:
        print("unknown native element ", node)
        view = EmptyView();
    }
    
    view = applyViewModifiers(to: view, from: props)
    return AnyView(view)
}

public struct JSView: View {
    var renderFn: JSValue
    // TODO: should we put in JSValues here directly? How do they equate?
    var props: [String: Any]
    @State var state: [String: Any]? = nil
    
    public init(_ renderFn: JSValue, props: [String: Any] = [:]) {
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

    public var body: some View {
        let context = renderFn.context!;
        let jsProps = JSValue(object: props, in: context)!
        let jsState = JSValue(object: state, in: context)!
        let setStateCallback: @convention(block) (JSValue) -> Void = { newState in
            self.setState(state: newState)
        }
        let jsSetState = JSValue(object: setStateCallback, in: context)!

        let node = renderFn.call(withArguments: [jsProps, jsState, jsSetState])!;
        return renderNode(node)
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
    case "systemGroupedBackground": return .yellow //Color(.systemGroupedBackground)
    default: return nil
    }
}
