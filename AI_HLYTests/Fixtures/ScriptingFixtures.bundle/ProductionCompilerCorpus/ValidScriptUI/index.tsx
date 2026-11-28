import { Button, Navigation, Text, VStack, useState } from "scripting"

function App() {
  const [count, setCount] = useState(0)
  return <VStack spacing={8}>
    <Text>Count {count}</Text>
    <Button title="Increment" action={() => setCount(value => value + 1)} />
  </VStack>
}

Navigation.present({ element: <App /> })
