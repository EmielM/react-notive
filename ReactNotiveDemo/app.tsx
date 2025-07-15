import { VStack, Text, Button, List, StatefulComponent, Component } from "react-notive";

type CounterProps = {
    label: string;
}

type CounterState = {
    count: number;
}

const Counter: StatefulComponent<CounterProps, CounterState> = (props, state, setState) => {
    const increase = () => {
        setState({count: state.count + 1});
    };

    return (
        <VStack spacing={10} padding={null} frame={{maxWidth: Infinity, maxHeight: Infinity}} background="systemGroupedBackground">
            <Text font="largeTitle" fontWeight="semibold">{props.label}</Text>
            <Text foregroundColor="gray">{`You tapped ${state.count} times`}</Text>
            <Button action={increase}>
                <Text padding={null} frame={{maxWidth: Infinity}} background="blue" foregroundColor="white" cornerRadius={10}>Tap me</Text>
            </Button>
            <List data={["a", "b", "c"]} rowContent={(item) => <Text>{`ITEM ${item}`}</Text>} />
        </VStack>
    );
}
Counter.initialState = {count: 1};

const App: Component = () => {
    return <Counter label="Hello World" />;
}

registerApp(App);