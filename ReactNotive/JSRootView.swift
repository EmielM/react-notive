import UIKit
import JavaScriptCore

class JSRootView: UIView {
    var context: JSContext?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemOrange
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func attachJSContext(_ context: JSContext) {
        self.context = context;
//        context.evaluateScript("""
//            log('Hello from RootView!');
//        """)
    }
}
