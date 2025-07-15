import SwiftUI
import JavaScriptCore

func renderNode(_ node: JSValue) -> AnyView {
    guard node.isObject, !node.isNull
    else {
        fatalError("renderNode not an object")
    }
    
    let type = node.objectForKeyedSubscript("type")!
    let props = node.objectForKeyedSubscript("props")!
    if type.isFunction {
        // Another component
        guard let props0: [String: JSValue] = props.bridge()
        else {
            fatalError("Could not unwrap props")
        }
        return AnyView(JSView(type, props: props0))
    }
    
    guard let typeString: String = type.bridge(),
          let factory = ViewRegistry.factories[typeString]
    else {
        print("unknown native element ", type)
        return AnyView(EmptyView())
    }
    
    guard let view: AnyView = factory(props)
    else {
        print("could not render ", type, " ", props)
        return AnyView(EmptyView())
    }
    
    let modifiedView = applyViewModifiers(to: view, from: props)
    return modifiedView
}

// Returns a swiftUI "content" closure, usually based based on jsx "children" prop
func getRenderer(forChildren: JSValue) -> () -> AnyView {
    if let children: [JSValue] = forChildren.bridge() {
        // Multiple children
        return {
            AnyView(ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                return renderNode(child)
            })
        }
    } else if forChildren.isObject && !forChildren.isNull {
        // Single child
        let singleChild = forChildren
        return {
            renderNode(singleChild)
        }
    } else {
        return {
            AnyView(EmptyView())
        }
    }
}

public struct JSView: View {
    var renderFn: JSValue
    // TODO: check if this works
    // - Do JSValues equate correctly?
    // - Can be a JSValue on top-level as well?
    var props: [String: JSValue]
    @State var state: [String: JSValue]? = nil
    
    public init(_ renderFn: JSValue, props: [String: JSValue] = [:]) {
        self.renderFn = renderFn
        self.props = props
        if self._state.wrappedValue == nil {
            // JSView lifecycle is shorter than @State vars in SwiftUI. Only initialize to
            // initialState when nil. TODO: do this nicer.
            if let initialState: [String: JSValue] = renderFn.objectForKeyedSubscript("initialState")?.bridge() {
                self._state = State(initialValue: initialState)
            } else {
                // non-stateful component, but fill it with something so this path is not hit anymore
                self._state = State(initialValue: [:])
            }
        }
    }
    
    var componentName: String {
        // TODO: fix
        renderFn.objectForKeyedSubscript("name").toString()
    }
    
    func setState(state: JSValue) {
        let mergedState: [String: JSValue] = state.bridge()!
        self.state = self.state!.merging(mergedState) { (_, new) in new }
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


func applyViewModifiers(to view: some View, from props: JSValue) -> AnyView {
    var modifiedView: any View = view

    // Always apply props in the same order, as it matters in SwiftUI how things are applioed
    // - It does mean we're not as versatile from javascript
    // - Consider: using multi-props argument, support ordering here?

    if let padding = props["padding"], padding.isNull {
        modifiedView = modifiedView.padding()
    } else if let padding: Double = props["padding"]?.bridge() {
        modifiedView = modifiedView.padding(padding.toCGFloat())
    } else if let padding: [String: Double] = props["padding"]?.bridge() {
        modifiedView = modifiedView.padding(EdgeInsets(
            top: (padding["top"] ?? 0.0).toCGFloat(),
            leading: (padding["top"] ?? 0.0).toCGFloat(),
            bottom: (padding["top"] ?? 0.0).toCGFloat(),
            trailing: (padding["top"] ?? 0.0).toCGFloat()
        ))
    }
    
    if let frame: [String: Double] = props["frame"]?.bridge() {
        modifiedView = modifiedView.frame(
            width: frame["width"]?.toCGFloat(),
            height: frame["height"]?.toCGFloat(),
            alignment: .center
        ).frame(
            maxWidth: frame["maxWidth"]?.toCGFloat(),
            maxHeight: frame["maxHeight"]?.toCGFloat()
        )
    }

    if let transitionName: String = props["transition"]?.bridge(),
       let transition = makeTransition(named: transitionName) {
        modifiedView = modifiedView.transition(transition)
    }
    
    if let opacity: Double = props["opacity"]?.bridge() {
        modifiedView = modifiedView.opacity(opacity)
    }

    if let foregroundColorName: String = props["foregroundColor"]?.bridge(),
       let foregroundColor = makeColor(named: foregroundColorName) {
        modifiedView = modifiedView.foregroundColor(foregroundColor)
    }

    if let backgroundName: String = props["background"]?.bridge(),
       let background = makeColor(named: backgroundName) {
        modifiedView = modifiedView.background(background)
    }
    
    if let font: String = props["font"]?.bridge() {
        switch font {
        case "largeTitle": modifiedView = modifiedView.font(.largeTitle)
        case "title": modifiedView = modifiedView.font(.title)
        case "headline": modifiedView = modifiedView.font(.headline)
        case "body": modifiedView = modifiedView.font(.body)
        default: break
        }
    }
    
    if let fontWeight: String = props["fontWeight"]?.bridge() {
        switch fontWeight {
        case "semibold": modifiedView = modifiedView.fontWeight(.semibold)
        case "bold": modifiedView = modifiedView.fontWeight(.bold)
        case "regular": modifiedView = modifiedView.fontWeight(.regular)
        default: break
        }
    }

    if let cornerRadius: Double = props["cornerRadius"]?.bridge() {
        modifiedView = modifiedView.cornerRadius(CGFloat(cornerRadius))
    }

    return AnyView(modifiedView)
}

extension Double {
    func toCGFloat() -> CGFloat {
        // (Negative) infinity should be preserved by this cast
        return CGFloat(self)
    }
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
