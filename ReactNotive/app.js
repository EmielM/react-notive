// h() helper makes things lazily executable by native

function Counter(props, state, setState) {
    console.log("counter component ", props)
    h("VStack", {background: 'red'}, () => {
        // or: h({background: 'red'}); ?
        h("Text", {content: `${props.text}: ${state.count}`});
        
        const increase = () => {
            setState({count: state.count + 1});
        };
        
        h("Button", {action: increase}, () => {
            h("Text", {content: "Tap me"});
        });
    });
}
Counter.initialState = {count: 0};

function App() {
    h(Counter, {text: "hoi"})
}
