#include <Python/Python.h>
#include <TargetConditionals.h>
#include "PythonRuntimeBridge.h"
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <sstream>

// One linked provider table supplies registration, Python registry and the
// read-only host catalog. Downloaded data can never add a provider here.
static constexpr char nativeModuleName[] = "_hanlin_native";
static PyObject *InitializeHanlinNative(void);
struct BuiltinProvider {
    const char *distribution;
    const char *version;
    const char *module;
    PyObject *(*initialize)(void);
    std::atomic<bool> registered{false};
    std::atomic<bool> initializationObserved{false};
};
static BuiltinProvider providers[] = {
    {"hanlin-native", "1.0.0", nativeModuleName, InitializeHanlinNative}
};
#if defined(__arm64__) || defined(__aarch64__) || defined(_M_ARM64)
static constexpr const char *architecture = "arm64";
#elif defined(__x86_64__) || defined(_M_X64)
static constexpr const char *architecture = "x86_64";
#else
static constexpr const char *architecture = "unknown";
#endif

char *HanlinPythonNativeExtensionCatalogJSON(void) {
    // No Python C API, GIL, job queue, initialization or import on this path.
    // Atomics distinguish registration from a previously observed module initialization;
    // neither fact promotes the service snapshot to Ready or proves signing.
    try {
        std::ostringstream output;
        output << '[';
        bool first = true;
        for (const auto &provider : providers) {
            const bool initialized = provider.initializationObserved.load();
            const bool registered = provider.registered.load();
            if (!first) output << ',';
            first = false;
            // Names/versions are canonical ASCII constants in the linked table.
            output << "{\"distribution\":" << std::quoted(provider.distribution)
                << ",\"version\":" << std::quoted(provider.version)
                << ",\"module\":" << std::quoted(provider.module)
                << ",\"architecture\":" << std::quoted(architecture)
                << ",\"pythonMajor\":" << PY_MAJOR_VERSION
                << ",\"pythonMinor\":" << PY_MINOR_VERSION
                << ",\"linkage\":\"signed-app-builtin\""
                << ",\"simulator\":" << (TARGET_OS_SIMULATOR ? "true" : "false")
                << ",\"registeredInittab\":" << (registered ? "true" : "false")
                << ",\"initializationObserved\":" << (initialized ? "true" : "false") << '}';
        }
        output << ']';
        const std::string json = output.str();
        char *copy = static_cast<char *>(std::malloc(json.size() + 1));
        if (copy) std::memcpy(copy, json.c_str(), json.size() + 1);
        return copy;
    } catch (...) { return nullptr; }
}

static PyObject *NativeChallenge(PyObject *, PyObject *nonce) {
    if (!PyUnicode_Check(nonce)) {
        PyErr_SetString(PyExc_TypeError, "nonce must be a string");
        return nullptr;
    }
    return Py_BuildValue("{s:O,s:s,s:s}", "nonce", nonce,
                         "engine", "cpython-native-extension", "linkage", "signed-app-builtin");
}

static PyObject *NativeRegistry(PyObject *, PyObject *) {
    PyObject *list = PyList_New(0);
    if (!list) return nullptr;
    for (const auto &provider : providers) {
        PyObject *entry = Py_BuildValue("{s:s,s:s,s:s,s:s,s:i,s:i,s:s,s:O,s:O,s:O}",
            "distribution", provider.distribution, "version", provider.version, "module", provider.module,
            "architecture", architecture, "pythonMajor", PY_MAJOR_VERSION, "pythonMinor", PY_MINOR_VERSION,
            "linkage", "signed-app-builtin", "simulator", TARGET_OS_SIMULATOR ? Py_True : Py_False,
            "registeredInittab", provider.registered.load() ? Py_True : Py_False,
            "initializationObserved", provider.initializationObserved.load() ? Py_True : Py_False);
        if (!entry || PyList_Append(list, entry) != 0) {
            Py_XDECREF(entry); Py_DECREF(list); return nullptr;
        }
        Py_DECREF(entry);
    }
    return list;
}

static PyMethodDef nativeMethods[] = {
    {"challenge", NativeChallenge, METH_O, "Return the caller's nonce from the compiled extension."},
    {"registry", NativeRegistry, METH_NOARGS, "List extensions actually linked into this app."},
    {nullptr, nullptr, 0, nullptr}
};
static PyModuleDef nativeModule = {PyModuleDef_HEAD_INIT, nativeModuleName, nullptr, -1, nativeMethods};

static PyObject *InitializeHanlinNative(void) {
    PyObject *module = PyModule_Create(&nativeModule);
    if (module) providers[0].initializationObserved.store(true);
    return module;
}

int HanlinPythonRegisterBundledExtensions(void) {
    for (auto &provider : providers) {
        if (provider.registered.load()) continue;
        if (PyImport_AppendInittab(provider.module, provider.initialize) != 0) return -1;
        provider.registered.store(true);
    }
    return 0;
}
