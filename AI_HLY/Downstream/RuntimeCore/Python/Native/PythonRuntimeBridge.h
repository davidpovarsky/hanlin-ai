#ifndef HanlinPythonRuntimeBridge_h
#define HanlinPythonRuntimeBridge_h

#ifdef __cplusplus
extern "C" {
#endif

const char *HanlinPythonVersion(void);
char *HanlinPythonExecute(const char *requestJSON);
void HanlinPythonFree(char *value);
void HanlinPythonRegisterExecution(const char *executionID);
void HanlinPythonCancelExecution(const char *executionID);
void HanlinPythonUnregisterExecution(const char *executionID);

#ifdef __cplusplus
}
#endif

#endif
