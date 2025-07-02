import type { Node } from "./index";

export const VStack = "VStack";
export const Text = "Text";
export const Button = "Button";

type Color = string;

type LayoutProps = {
  padding?: null | number;
  frame?: {
    maxWidth?: number;
    maxHeight?: number;
  };
  background?: Color;
  foregroundColor?: Color;
  cornerRadius?: number;
};

export type NativeElements = {
  [VStack]: {
    spacing?: number;
    children: Node[];
  } & LayoutProps;
  [Button]: {
    action: () => void;
    children: Node[] | Node;
  } & LayoutProps;
  [Text]: {
    font?: string;
    fontWeight?: "bold" | "semibold" | "medium" | "regular" | "light" | "thin";
    children: string; // Explicitly allow/force single string
  } & LayoutProps;
};
