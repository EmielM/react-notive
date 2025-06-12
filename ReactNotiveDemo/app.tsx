// h() helper makes things lazily executable by native

import { VStack, Text, Button } from "react-notive";

function Counter(props, state, setState) {
    const increase = () => {
        setState({count: state.count + 1});
    };

    return (
        <VStack spacing={20} padding={null} frame={{maxWidth: Infinity, maxHeight: Infinity}} background="systemGroupedBackground">
            <Text font="largeTitle" fontWeight="semibold">{props.label}</Text>
            <Text foregroundColor="gray">You tapped {state.count} times</Text>

            <Button action={increase}>
                <Text padding={null} frame={{maxWidth: Infinity}} background="blue" foregroundColor="white" cornerRadius={10}>Tap me</Text>
            </Button>
        </VStack>
    );
}
Counter.initialState = {count: 0};

function App() {
    return <Counter label="Hello World" />;
}
