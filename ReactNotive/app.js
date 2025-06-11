// h() helper makes things lazily executable by native

function Counter(props, state, setState) {
    h("VStack", {spacing: 20, padding: null, frame: {maxWidth: Infinity, maxHeight: Infinity}, background: 'systemGroupedBackground'}, () => {
        h("Text", {font: 'largeTitle', fontWeight: 'semibold'}, props.label);
        h("Text", {foregroundColor: 'gray'}, `You tapped ${state.count} times`);
        
        const increase = () => {
            setState({count: state.count + 1});
        };
        
        h("Button", {action: increase}, () => {
            h("Text", {padding: null, frame: {maxWidth: Infinity}, background: 'blue', foregroundColor: 'white', cornerRadius: 10}, "Tap me");
        });
    });
}
Counter.initialState = {count: 0};

function App() {
    h(Counter, {label: "Hello World"})
}
