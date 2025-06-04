class Node {
  constructor(type, args) {
    this.type = type;
    this.props = {};
    this.children = [];
    for (const arg of args) {
      if (arg instanceof Node || typeof arg === "string") {
        this.children.push(arg);
      } else if (typeof arg === "object" && arg) {
        this.props = { ...this.props, ...arg };
      }
    }
  }
}

const VStack = (...args) => new Node("VStack", args);
const Text = (...args) => new Node("Text", args);
const Button = (...args) => new Node("Button", args);

function component(renderFn, initialState) {
  const f = (...args) => {
    return new Node("Component", [
      { renderFn, initialState, [renderFn.name]: true },
      ...args,
    ]);
  };
  return f;
}

const Color = {
  Blue: "blue",
  White: "white",
};

var Counter = component(
  function Counter(props, state, setState) {
    console.log("Counter props=", Object.keys(props));
    const increase = () => {
      console.log("increase");
      setState({ count: state.count + 1 });
    };
    return VStack(
      Text({ content: `${props.label}: ${state.count}` }),
      Button(
        Text({
          content: "Tap me",
          background: Color.blue,
          foregroundColor: Color.white,
          cornerRadius: 8,
        }),
        { action: increase }
      )
    );
  },
  { count: 0 }
);

var App = component(function App(props) {
  console.log("App render called!");
  return Counter({ label: "count" });
});

async function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

/*async function main() {
    console.log("a");
    await sleep(3000);
    console.log("b");
    const r = 123;
    abc();
    console.log("r=" + r);
}

async function entry() {
    try {
        await main();
    } catch (e) {
        console.log("e: " + e);
    }
}

entry();*/
