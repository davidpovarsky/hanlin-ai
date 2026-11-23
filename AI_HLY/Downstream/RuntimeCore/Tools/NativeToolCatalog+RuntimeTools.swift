extension NativeToolCatalog {
    func registerRuntimeTools() {
        register(ExecuteLocalPythonTool())
        register(ExecuteJavaScriptTool())
        register(ExecuteTypeScriptTool())
        register(MiniAppAuthoringTool(operation: .sdk))
        register(MiniAppAuthoringTool(operation: .write))
        register(MiniAppAuthoringTool(operation: .validate))
        register(MiniAppAuthoringTool(operation: .build))
        register(MiniAppAuthoringTool(operation: .importPackage))
        register(ExecuteShellCommandTool())
        register(ListToolsTool())
        register(GetRuntimeCapabilitiesTool())
        register(GetRuntimeJobTool())
        register(ManageRuntimePackagesTool())
        register(ManageMCPServersTool())
        register(ExecuteSkillResourceTool())
        #if HANLIN_A2UI_POC
        register(PresentA2UITool())
        #endif
        register(TorahOCRExcerptTool())
        register(TorahIdentifyExcerptTool())
        register(TorahSearchTextTool())
        register(TorahGetSectionTool())
        register(TorahGetLinksTool())
        register(TorahGetTopicsTool())
        register(TorahOpenSourceTool())
    }
}
