"use strict";
AssistantTool.registerExecuteTool(async (parameters) => ({
    success: true,
    message: `script:${parameters.text}`,
}));
