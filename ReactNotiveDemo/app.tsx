import { VStack, Text, Button, List, StatefulComponent, Component } from "react-notive";

type CounterProps = {
    label: string;
}

type CounterState = {
    count: number;
    result: any;
}

async function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

const Counter: StatefulComponent<CounterProps, CounterState> = (props, state, setState, {task, onAppear}) => {
    const increase = () => {
        setState({count: state.count + 1});
    };

    task(async (signal) => {
        console.log('TASK!', signal, typeof AbortController);
        const response = await fetch(`https://jsonplaceholder.typicode.com/todos/${state.count}`, { signal });
        const result = await response.json();
        console.log('pre-sleep', state.count)
        await sleep(3000);
        console.log('post-sleep', state.count)
        setState({result}, signal);
    }, [state.count]);

    onAppear(() => {
        console.log('onAppear');
    });

    return (
        <VStack spacing={10} padding={null} frame={{maxWidth: Infinity, maxHeight: Infinity}} background="systemGroupedBackground">
            <Text font="largeTitle" fontWeight="semibold">{props.label}</Text>
            <Count count={state.count} />
            <Button action={increase}>
                <Text padding={null} frame={{maxWidth: Infinity}} background="blue" foregroundColor="white" cornerRadius={10}>Tap me</Text>
            </Button>
            <Text>{JSON.stringify(state.result)}</Text>
            <List data={["a", "b", "c"]} rowContent={(item) => <Text>{`ITEM ${item}`}</Text>} />
        </VStack>
    );
}
Counter.initialState = {count: 1, result: null};

const Count: Component<{count: number}> = (props, {onAppear, onDisappear}) => {
    console.log('Count render');
    onAppear(() => {
        console.log('Count onAppear');
    });
    onDisappear(() => {
        console.log('Count onDisappear');
    });
    return <Text foregroundColor="gray">{`YouX tapped ${props.count} times`}</Text>;
}

const App: Component = () => {
    return <Counter label="Hello World" />;
}

registerApp(App);
