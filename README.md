# ReactNotive

Quick idea: React-like JSX mapped directly onto SwiftUI. Very basic implementation.

Example use at [ReactNotiveDemo/app.tsx](ReactNotiveDemo/app.tsx)

Implementation:

- [ReactNotive/Sources/ReactNotive/ReactNotive.swift](ReactNotive/Sources/ReactNotive/ReactNotive.swift) mapping nodes to SwiftUI views
- [ReactNotive/index.ts](ReactNotive/index.ts) and [ReactNotive/nativeElements.ts](ReactNotive/nativeElements.ts) for the simple react-jsx implementation and typescript type guards

TODO:

- Implement useEffect of sorts
- Implement Provider/useContext stuff, to enforce statelessness!

Big future ideas:

- Enforce no state leakage and render over multiple JavaScriptCore VMs/threads!
- Android binding to [Compose](https://developer.android.com/develop/ui/compose/mental-model)
