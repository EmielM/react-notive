import SwiftUI
import ReactNotive

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
struct ReactNotiveDemoApp: App {
    var body: some Scene {
        WindowGroup {
            JSRoot()
//            DemoView()
        }
    }
}

