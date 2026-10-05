extension NativeToolCatalog {
    func registerRuntimeTools() {
        register(ExecuteLocalPythonTool())
        register(ExecuteJavaScriptTool())
        register(ExecuteTypeScriptTool())
        register(ExecuteShellCommandTool())
        register(ListToolsTool())
        register(GetRuntimeCapabilitiesTool())
        register(ManageRuntimePackagesTool())
        register(ExecuteSkillResourceTool())
    }
}
