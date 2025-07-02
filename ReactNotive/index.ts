import type { NativeElements } from "./nativeElements";

export { VStack, Text, Button } from "./nativeElements";

type AnyProps = Record<string, any>;
type AnyState = Record<string, any>;

// A component is a function that takes props and returns a node
// Define as const MyComponent: Component<MyComponentProps> = (props) => ...
export type Component<P extends AnyProps> = (props: P) => Node;

// A stateful component defines .initialState and receives state and setState
// Define as const MyComponent: StatefulComponent<MyComponentProps, MyComponentState> = (props, state, setState) => ...
export type StatefulComponent<P extends AnyProps, S extends AnyState> = {
  (props: P, state: S, setState: (state: S) => void): Node;
  initialState: S;
};

type AnyType =
  | Component<any>
  | StatefulComponent<any, any>
  | keyof NativeElements;

export type Node = [AnyType, AnyProps];

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

export function jsx<T extends AnyType>(
  type: T,
  props: Omit<ExtractProps<T>, "children">,
  children?: ExtractProps<T>["children"]
): Node {
  return [type, children ? { ...props, children } : props];
}

declare global {
  namespace JSX {
    type Element = Node;

    interface ElementChildrenAttribute {
      children: {};
    }

    type IntrinsicElements = NativeElements;
    // type LibraryManagedAttributes<T extends AnyType, P> = ExtractProps<T>;
  }
}
