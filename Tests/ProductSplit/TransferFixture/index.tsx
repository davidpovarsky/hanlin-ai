import { Button, Navigation, Text, VStack, useState } from "scripting"

function App() {
  const [value, setValue] = useState(Storage.get<string>("copy-value") ?? "Not saved")
  return <VStack spacing={8}>
    <Text>{value}</Text>
    <Button title="Save transfer value" action={() => {
      const saved = "Saved by the original ScriptUI runtime"
      Storage.set("copy-value", saved)
      setValue(saved)
    }} />
  </VStack>
}

Navigation.present({ element: <App /> })
