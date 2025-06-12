export const VStack = "VStack";
export const Text = "Text";
export const Button = "Button";

export function jsx(type: any, props: any, ...children: any[]): any {
  return h(type, props, { children });
}

export const jsxFragment = (props: { children: any }) => props.children;
