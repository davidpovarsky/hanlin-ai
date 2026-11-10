#include <Python/Python.h>
#include <TargetConditionals.h>
#include "PythonRuntimeBridge.h"

// Linked into the app's signed executable, never dlopen'd from downloaded data.
// Additional built-in extension providers belong in this explicit registration table.
static PyObject *NativeChallenge(PyObject *, PyObject *nonce) {
    if (!PyUnicode_Check(nonce)) {
        PyErr_SetString(PyExc_TypeError, "nonce must be a string");
        return nullptr;
    }
    return Py_BuildValue("{s:O,s:s,s:s}", "nonce", nonce,
                         "engine", "cpython-native-extension", "linkage", "signed-app-builtin");
}

static PyObject *NativeRegistry(PyObject *, PyObject *) {
#if defined(__arm64__) || defined(__aarch64__)
    const char *architecture = "arm64";
#elif defined(__x86_64__)
    const char *architecture = "x86_64";
#else
    const char *architecture = "unknown";
#endif
    return Py_BuildValue("[{s:s,s:s,s:s,s:s,s:i,s:i,s:s,s:O}]",
        "distribution", "hanlin-native", "version", "1.0.0", "module", "_hanlin_native",
        "architecture", architecture, "pythonMajor", PY_MAJOR_VERSION, "pythonMinor", PY_MINOR_VERSION,
        "linkage", "signed-app-builtin", "simulator", TARGET_OS_SIMULATOR ? Py_True : Py_False);
}

static PyMethodDef nativeMethods[] = {
    {"challenge", NativeChallenge, METH_O, "Return the caller's nonce from the compiled extension."},
    {"registry", NativeRegistry, METH_NOARGS, "List extensions actually linked into this app."},
    {nullptr, nullptr, 0, nullptr}
};
static PyModuleDef nativeModule = {PyModuleDef_HEAD_INIT, "_hanlin_native", nullptr, -1, nativeMethods};

static PyObject *InitializeHanlinNative(void) { return PyModule_Create(&nativeModule); }

int HanlinPythonRegisterBundledExtensions(void) {
    return PyImport_AppendInittab("_hanlin_native", InitializeHanlinNative);
}
