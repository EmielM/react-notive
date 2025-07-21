import type { NativeElements } from "./nativeElements";

export { VStack, Text, Button, List } from "./nativeElements";

// Consider: maintain as index.d.ts directly for better composite package support without build step

type AnyProps = Record<string, any>;
type AnyState = Record<string, any>;

interface AbortSignal {
  aborted: boolean;
  throwIfAborted(): void;
}

type Lifecycle = {
  onAppear: (callback: () => void) => void;
  onDisappear: (callback: () => void) => void;
  task: (
    callback: (signal: AbortSignal) => Promise<void>,
    dependencies: any[]
  ) => void;
};

// A component is a function that takes props and returns a node
// Define as const MyComponent: Component<MyComponentProps> = (props, lifecycle) => ...
// Template default is propertyless: const App: Component = () => {}
export type Component<P extends AnyProps = {}> = (
  props: P,
  lifecycle: Lifecycle
) => Node;

// type StatefulLifecycle = Lifecycle & {
//   state: AnyState;
//   setState: (state: Partial<AnyState>, signal?: AbortSignal) => void;
// };

// A stateful component defines .initialState and receives state and setState
// Define as const MyComponent: StatefulComponent<MyComponentProps, MyComponentState> = ({props, state, setState, lifecycle}) => ...
export type StatefulComponent<P extends AnyProps, S extends AnyState> = {
  (
    props: P,
    state: S,
    setState: (state: Partial<S>, signal?: AbortSignal) => void,
    lifecycle: Lifecycle
  ): Node;
  initialState: S;
};

type AnyType =
  | Component<any>
  | StatefulComponent<any, any>
  | keyof NativeElements;

// Consider: call this Element instead of Node?
export type Node = { type: AnyType; props: AnyProps };

export type ExtractProps<C extends AnyType> = C extends StatefulComponent<
  infer P,
  any
>
  ? P
  : C extends Component<infer P>
  ? P
  : C extends keyof NativeElements
  ? NativeElements[C]
  : never;

export function jsx<T extends AnyType>(type: T, props: ExtractProps<T>): Node {
  return { type, props };
}

// App component has/receives no props yet
type AppProps = {};

declare global {
  namespace JSX {
    type Element = Node;

    interface ElementChildrenAttribute {
      children: {};
    }

    type IntrinsicElements = NativeElements;
  }

  function registerApp(app: Component<AppProps>): void;
}
