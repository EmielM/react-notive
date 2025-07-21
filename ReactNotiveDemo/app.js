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
async function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
var Counter = (props, state, setState, { task, onAppear }) => {
  const increase = () => {
    setState({ count: state.count + 1 });
  };
  task(async (signal) => {
    console.log("TASK!", signal, typeof AbortController);
    const response = await fetch(`https://jsonplaceholder.typicode.com/todos/${state.count}`, { signal });
    const result = await response.json();
    console.log("pre-sleep", state.count);
    await sleep(3000);
    console.log("post-sleep", state.count);
    setState({ result }, signal);
  }, [state.count]);
  onAppear(() => {
    console.log("onAppear");
  });
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
      /* @__PURE__ */ jsx(Count, {
        count: state.count
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
      /* @__PURE__ */ jsx(Text, {
        children: JSON.stringify(state.result)
      }, undefined, false, undefined, this),
      /* @__PURE__ */ jsx(List, {
        data: ["a", "b", "c"],
        rowContent: (item) => /* @__PURE__ */ jsx(Text, {
          children: `ITEM ${item}`
        }, undefined, false, undefined, this)
      }, undefined, false, undefined, this)
    ]
  }, undefined, true, undefined, this);
};
Counter.initialState = { count: 1, result: null };
var Count = (props, { onAppear, onDisappear }) => {
  console.log("Count render");
  onAppear(() => {
    console.log("Count onAppear");
  });
  onDisappear(() => {
    console.log("Count onDisappear");
  });
  return /* @__PURE__ */ jsx(Text, {
    foregroundColor: "gray",
    children: `YouX tapped ${props.count} times`
  }, undefined, false, undefined, this);
};
var App = () => {
  return /* @__PURE__ */ jsx(Counter, {
    label: "Hello World"
  }, undefined, false, undefined, this);
};
registerApp(App);
