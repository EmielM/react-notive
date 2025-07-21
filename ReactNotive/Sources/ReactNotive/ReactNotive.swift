import SwiftUI
import JavaScriptCore

func renderNode(_ node: JSValue) -> AnyView {
    guard node.isObject, !node.isNull
    else {
        print("renderNode not an object: ", node)
        return AnyView(EmptyView())
    }
    
    guard let type = node.objectForKeyedSubscript("type"),
          let props = node.objectForKeyedSubscript("props")
    else {
        print("type or props missing: ", node)
        return AnyView(EmptyView())
    }
    if type.isFunction {
        // Another component
        guard let propsDict: [String: JSValue] = props.bridge()
        else {
            print("could not unwrap props: ", props)
            return AnyView(EmptyView())
        }
        return AnyView(JSView(type, props: propsDict))
    }
    
    guard let typeString: String = type.bridge(),
          let factory = ViewRegistry.factories[typeString]
    else {
        print("unknown native element: ", type)
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
            }
        }
    }
    
    var componentName: String {
        renderFn["name"]?.bridge() ?? "<unknown>"
    }
    
    func setState(_ newState: [String: JSValue], abortSignal: JSAbortSignal? = nil) {
        if abortSignal?.aborted == true {
            print(self.componentName, ".setState: stale value, task was aborted")
            return
        }
        self.state = self.state!.merging(newState) { (_, new) in new }
    }

    public var body: some View {
        let context = renderFn.context!;
        
        let jsProps = JSValue(object: props, in: context)!
        
        let jsLifecycle = JSValue(newObjectIn: context)!
        var viewModifiers: [(AnyView) -> AnyView] = [];
        let onAppearFunction: @convention(block) (JSValue) -> Void = { onAppear in
            viewModifiers.append({ view in AnyView(view.onAppear { onAppear.call(withArguments:[]) }) });
        }
        jsLifecycle.setObject(onAppearFunction, forKeyedSubscript: "onAppear" as NSString);

        let onDisappearFunction: @convention(block) (JSValue) -> Void = { onDisappear in
            viewModifiers.append({ view in AnyView(view.onDisappear { onDisappear.call(withArguments:[]) }) });
        }
        jsLifecycle.setObject(onDisappearFunction, forKeyedSubscript: "onDisappear" as NSString);

        let taskFunction: @convention(block) (JSValue, JSValue) -> Void = { taskCallback, deps in
            guard let depsArray: [JSValue] = deps.bridge()
            else {
                print("invalid task() invocation: ", deps)
                return
            }
            print("task registered ", task, depsArray)
            if #available(iOS 17, *) {
                viewModifiers.append({ view in AnyView(view.task(id:depsArray) { @MainActor () async in
                    let uuid = UUID()
                    print(uuid, ": run")
                    let abortController = JSAbortController()
                    let signal = abortController.signal

                    do {
                        let result = try await withTaskCancellationHandler {
                            try await taskCallback.callAndAwait(withArguments: [signal])
                        } onCancel: {
                            print(uuid, ": invoke abort")
                            _ = abortController.abort()
                        }
                        print(uuid, ": done")
                    } catch {
                        print(uuid, ": js error ", error)
                    }
                }) });
            }
        }
        jsLifecycle.setObject(taskFunction, forKeyedSubscript: "task" as NSString);

        let node: JSValue
        if state != nil {
            // Stateful component
            let jsState = JSValue(object: state, in: context)!
            let setStateFunction: @convention(block) (JSValue, JSValue) -> Void = {
                guard let newState: [String: JSValue] = $0.bridge()
                else {
                    print("invalid newState: ", $0)
                    return
                }
                let abortSignal = $1.toObject() as? JSAbortSignal
                self.setState(newState, abortSignal:abortSignal)
            }
            let jsSetState = JSValue(object: setStateFunction, in: context)!
            node = renderFn.call(withArguments: [jsProps, jsState, jsSetState, jsLifecycle])!;
        } else {
            // Stateless component
            node = renderFn.call(withArguments: [jsProps, jsLifecycle])!;
        }

        var view = renderNode(node)
        for viewModifier in viewModifiers {
            view = viewModifier(view)
        }
        return view
    }
}


func applyViewModifiers(to view: some View, from props: JSValue) -> AnyView {
    var modifiedView: any View = view

    // Always apply props in the same order, as it matters in SwiftUI how things are applied
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
