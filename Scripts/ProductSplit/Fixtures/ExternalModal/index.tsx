import { Button, Navigation, Text, VStack, useEffect, useState } from "scripting"

const bridge = (globalThis as any).MiniApps

function App() {
  const [isPresented, setIsPresented] = useState(false)
  const [count, setCount] = useState(0)
  const [requestID, setRequestID] = useState("")
  const [input, setInput] = useState("")
  const [documentID, setDocumentID] = useState("")
  const [error, setError] = useState("")

  useEffect(() => {
    bridge.getContext().then(context => {
      setRequestID(String(context.id).toLowerCase())
      setInput(context.inputs[0].text)
      setDocumentID(context.source.documentID)
    }).catch(value => setError(String(value)))
  }, [])

  async function complete() {
    try {
      const context = await bridge.getContext()
      const afterID = String(context.id).toLowerCase()
      if (afterID !== requestID || context.inputs[0].text !== input || context.source.documentID !== documentID) {
        throw new Error("External invocation context changed across modal presentation")
      }
      await bridge.complete({
        operation: "display",
        items: [{ kind: "text", text: `modal-survived:${afterID}:counter=${count}:input=${input}` }],
        message: "Modal invocation survived",
        metadata: { beforeRequestID: requestID, afterRequestID: afterID, counter: String(count), documentID }
      })
    } catch (value) { setError(String(value)) }
  }

  return <VStack spacing={16}>
    <Text>External modal fixture</Text>
    <Text>{`Context ${requestID}`}</Text>
    <Text>{`Input ${input}`}</Text>
    <Text>{`Counter ${count}`}</Text>
    <Button title="Increment counter" action={() => setCount(value => value + 1)} />
    <Button title="Open nested full screen" action={() => setIsPresented(true)} fullScreenCover={{
      isPresented,
      onChanged: setIsPresented,
      content: <VStack spacing={20}>
        <Text>Nested modal is active</Text>
        <Text>{`Modal context ${requestID}`}</Text>
        <Button title="Dismiss nested full screen" action={() => setIsPresented(false)} />
      </VStack>
    }} />
    <Button title="Complete modal invocation" action={complete} />
    <Text>{error ? `Error ${error}` : "No invocation error"}</Text>
  </VStack>
}

Navigation.present({ element: <App /> })
