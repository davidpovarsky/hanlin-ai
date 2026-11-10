#ifndef HanlinPythonRuntimeBridge_h
#define HanlinPythonRuntimeBridge_h

#ifdef __cplusplus
extern "C" {
#endif

const char *HanlinPythonVersion(void);
int HanlinPythonRegisterBundledExtensions(void);
// Read-only malloc-owned JSON; release with HanlinPythonFree. Never initializes Python.
char *HanlinPythonNativeExtensionCatalogJSON(void);
char *HanlinPythonExecute(const char *requestJSON);
void HanlinPythonFree(char *value);
void HanlinPythonRegisterExecution(const char *executionID);
void HanlinPythonCancelExecution(const char *executionID);
void HanlinPythonUnregisterExecution(const char *executionID);

#ifdef __cplusplus
}
#endif

#endif
