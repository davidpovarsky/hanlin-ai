type EchoParameters = {
  text: string
}

AssistantTool.registerExecuteTool<EchoParameters>(async (parameters) => ({
  success: true,
  message: `script:${parameters.text}`,
}))
