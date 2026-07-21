#ifndef HanlinPythonRuntimeBridge_h
#define HanlinPythonRuntimeBridge_h

#ifdef __cplusplus
extern "C" {
#endif

const char *HanlinPythonVersion(void);
char *HanlinPythonExecute(const char *requestJSON);
void HanlinPythonFree(char *value);

#ifdef __cplusplus
}
#endif

#endif
