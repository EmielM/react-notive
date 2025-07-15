// ../ReactNotive/nativeElements.ts
var VStack = "VStack";
var Text = "Text";
var Button = "Button";
var List = "List";

// ../ReactNotive/index.ts
function jsx(type, props) {
  return { type, props };
}
// app.tsx
var Counter = (props, state, setState) => {
  const increase = () => {
    setState({ count: state.count + 1 });
  };
  return /* @__PURE__ */ jsx(VStack, {
    spacing: 10,
    padding: null,
    frame: { maxWidth: Infinity, maxHeight: Infinity },
    background: "systemGroupedBackground",
    children: [
      /* @__PURE__ */ jsx(Text, {
        font: "largeTitle",
        fontWeight: "semibold",
        children: props.label
      }, undefined, false, undefined, this),
      /* @__PURE__ */ jsx(Text, {
        foregroundColor: "gray",
        children: `You tapped ${state.count} times`
      }, undefined, false, undefined, this),
      /* @__PURE__ */ jsx(Button, {
        action: increase,
        children: /* @__PURE__ */ jsx(Text, {
          padding: null,
          frame: { maxWidth: Infinity },
          background: "blue",
          foregroundColor: "white",
          cornerRadius: 10,
          children: "Tap me"
        }, undefined, false, undefined, this)
      }, undefined, false, undefined, this),
      /* @__PURE__ */ jsx(List, {
        data: ["a", "b", "c"],
        idFunction: (item) => item,
        rowContent: (item) => /* @__PURE__ */ jsx(Text, {
          children: `ITEM ${item}`
        }, undefined, false, undefined, this)
      }, undefined, false, undefined, this)
    ]
  }, undefined, true, undefined, this);
};
Counter.initialState = { count: 1 };
var App = () => {
  return /* @__PURE__ */ jsx(Counter, {
    label: "Hello World"
  }, undefined, false, undefined, this);
};
registerApp(App);
