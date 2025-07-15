import SwiftUI
import JavaScriptCore

protocol ViewFactory {
    static func from(props: JSValue) -> AnyView?
}

enum ViewRegistry {
    static let factories: [String: (JSValue) -> AnyView?] = [
        "List": ListFactory.from,
        "VStack": VStackFactory.from,
        "Button": ButtonFactory.from,
        "Text": TextFactory.from,
    ]
}

enum ListFactory: ViewFactory {
    static func from(props: JSValue) -> AnyView? {
        guard let data: [JSValue] = props["data"]?.bridge(),
              let rowContent: (JSValue) -> JSValue = props["rowContent"]?.bridge(),
              let idFunction: ((JSValue) -> String)? = props["idFunction"]?.bridge(),
              let idKey: String? = props["id"]?.bridge()
        else {
            return nil
        }

        struct Row: Identifiable {
            let item: JSValue
            let idFunction: ((JSValue) -> String)?

            var id: String {
                if let fn = idFunction {
                    return fn(item)
                }
                return item.toString()
            }
        }

        let rows = data.map { Row(item: $0, idFunction: idFunction ) }

        return AnyView(
            List(rows) { row in
                let jsView = rowContent(row.item)
                renderNode(jsView)
            }
        )
    }
}

enum VStackFactory: ViewFactory {
    static func from(props: JSValue) -> AnyView? {
        guard let children: JSValue = props["children"],
              let spacing: Double? = props["spacing"]?.bridge()
        else {
            return nil
        }
        
        let content = getRenderer(forChildren: children)
        return AnyView(
            VStack(spacing: spacing?.toCGFloat(), content:content)
        )
    }
}

enum ButtonFactory: ViewFactory {
    static func from(props: JSValue) -> AnyView? {
        guard let children: JSValue = props["children"],
              let action: () -> Void = props["action"]?.bridge()
        else {
            return nil
        }
        
        let label = getRenderer(forChildren: children)
        return AnyView(
            Button(action: action, label:label)
        );
    }
}

enum TextFactory: ViewFactory {
    static func from(props: JSValue) -> AnyView? {
        guard let children: String = props["children"]?.bridge()
        else {
            return nil
        }
        return AnyView(Text(children))
    }
}
