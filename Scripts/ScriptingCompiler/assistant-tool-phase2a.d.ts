type AssistantToolResult = {
  success: boolean
  message: string
}

type AssistantToolExecuteFn<P> = (
  params: P
) => Promise<AssistantToolResult> | AssistantToolResult

declare const AssistantTool: {
  registerExecuteTool<P>(execute: AssistantToolExecuteFn<P>): (
    params: P
  ) => Promise<AssistantToolResult>
}
