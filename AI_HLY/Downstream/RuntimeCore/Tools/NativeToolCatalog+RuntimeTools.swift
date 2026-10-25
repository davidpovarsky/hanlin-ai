extension NativeToolCatalog {
    func registerRuntimeTools() {
        register(ExecuteLocalPythonTool())
        register(ExecuteJavaScriptTool())
        register(ExecuteTypeScriptTool())
        register(ExecuteShellCommandTool())
        register(ListToolsTool())
        register(GetRuntimeCapabilitiesTool())
        register(ManageRuntimePackagesTool())
        register(ManageMCPServersTool())
        register(ExecuteSkillResourceTool())
        register(TorahOCRExcerptTool())
        register(TorahIdentifyExcerptTool())
        register(TorahSearchTextTool())
        register(TorahGetSectionTool())
        register(TorahGetLinksTool())
        register(TorahGetTopicsTool())
        register(TorahOpenSourceTool())
    }
}
