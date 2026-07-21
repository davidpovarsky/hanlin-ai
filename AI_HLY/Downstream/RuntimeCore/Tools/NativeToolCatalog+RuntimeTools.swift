extension NativeToolCatalog {
    func registerRuntimeTools() {
        register(ExecuteLocalPythonTool())
        register(ExecuteJavaScriptTool())
        register(ExecuteTypeScriptTool())
        register(ExecuteShellCommandTool())
    }
}
