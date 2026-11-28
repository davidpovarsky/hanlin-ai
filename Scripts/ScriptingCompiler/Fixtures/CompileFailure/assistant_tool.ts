type InvalidParameters = {
  text: string
}

AssistantTool.registerExecuteTool<InvalidParameters>(async (parameters) => ({
  success: true,
  message: parameters.missingProperty,
}))
