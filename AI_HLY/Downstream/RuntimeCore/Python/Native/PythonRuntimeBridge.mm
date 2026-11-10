#include "PythonRuntimeBridge.h"
#include <Foundation/Foundation.h>
#include <Python/Python.h>
#include "PythonCancellationContext.hpp"
#include <mutex>
#include <atomic>
#include <memory>
#include <string>
#include <unordered_map>

static std::once_flag initializationFlag;
static NSString *initializationError = nil;
static std::mutex cancellationMutex;
static std::unordered_map<std::string, std::shared_ptr<std::atomic<bool>>> cancellationFlags;

void HanlinPythonRegisterExecution(const char *executionID) {
    if (!executionID) return;
    std::lock_guard<std::mutex> guard(cancellationMutex);
    cancellationFlags.emplace(executionID, std::make_shared<std::atomic<bool>>(false));
}

void HanlinPythonCancelExecution(const char *executionID) {
    if (!executionID) return;
    std::lock_guard<std::mutex> guard(cancellationMutex);
    auto found = cancellationFlags.find(executionID);
    if (found != cancellationFlags.end()) found->second->store(true);
}

void HanlinPythonUnregisterExecution(const char *executionID) {
    if (!executionID) return;
    std::lock_guard<std::mutex> guard(cancellationMutex);
    cancellationFlags.erase(executionID);
}

static char *CopyUTF8(NSString *value) {
    const char *utf8 = value.UTF8String ?: "";
    size_t length = strlen(utf8);
    char *copy = static_cast<char *>(malloc(length + 1));
    if (copy) memcpy(copy, utf8, length + 1);
    return copy;
}

static NSString *StatusMessage(PyStatus status) {
    if (status.err_msg) return [NSString stringWithUTF8String:status.err_msg];
    return @"Embedded Python initialization failed.";
}

static void InitializePython(void) {
    std::call_once(initializationFlag, [] {
        if (HanlinPythonRegisterBundledExtensions() != 0) {
            initializationError = @"Failed to register bundled Python native extensions.";
            return;
        }
        NSString *resources = NSBundle.mainBundle.resourcePath;
        NSString *pythonHome = [resources stringByAppendingPathComponent:@"python"];
        NSString *frameworksPath = NSBundle.mainBundle.privateFrameworksPath;
        setenv("PYTHONHOME", pythonHome.UTF8String, 1);
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
        setenv("PYTHONUTF8", "1", 1);
        // Embedded OpenSSL has no iOS Keychain-backed default CA file. Supply
        // the pinned, unmodified Mozilla roots; never weaken certificate checks.
        NSString *certificates = [NSBundle.mainBundle pathForResource:@"HanlinPythonCACertificates" ofType:@"pem"];
        if (!certificates) {
            initializationError = @"The embedded Python CA certificate bundle is missing.";
            return;
        }
        setenv("SSL_CERT_FILE", certificates.UTF8String, 0);

        if (frameworksPath) {
            setenv("DYLD_FRAMEWORK_PATH", frameworksPath.UTF8String, 1);
            setenv("DYLD_LIBRARY_PATH", frameworksPath.UTF8String, 1);
        }

        PyPreConfig preconfig;
        PyPreConfig_InitIsolatedConfig(&preconfig);
        preconfig.utf8_mode = 1;
        PyStatus status = Py_PreInitialize(&preconfig);
        if (PyStatus_Exception(status)) { initializationError = StatusMessage(status); return; }

        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.buffered_stdio = 0;
        config.write_bytecode = 0;
        config.install_signal_handlers = 1;
        config.use_system_logger = 1;
        status = PyConfig_SetBytesString(&config, &config.home, pythonHome.UTF8String);
        if (!PyStatus_Exception(status)) {
            status = PyConfig_SetBytesString(&config, &config.program_name, "Hanlin Embedded Python");
        }
        if (!PyStatus_Exception(status)) status = Py_InitializeFromConfig(&config);
        PyConfig_Clear(&config);
        if (PyStatus_Exception(status)) { initializationError = StatusMessage(status); return; }
        PyEval_SaveThread();
    });
}

const char *HanlinPythonVersion(void) {
    InitializePython();
    return initializationError ? nullptr : Py_GetVersion();
}

char *HanlinPythonExecute(const char *requestJSON) {
    InitializePython();
    if (initializationError) {
        NSDictionary *response = @{ @"error": initializationError };
        NSData *data = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
        return CopyUTF8([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    }
    if (!requestJSON) return CopyUTF8(@"{\"error\":\"Missing Python execution request.\"}");

    NSData *requestData = [NSData dataWithBytes:requestJSON length:strlen(requestJSON)];
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:requestData options:0 error:nil];
    if (![request isKindOfClass:NSDictionary.class]) return CopyUTF8(@"{\"error\":\"Invalid Python execution request.\"}");

    NSString *executionID = [request[@"executionID"] isKindOfClass:NSString.class] ? request[@"executionID"] : @"";
    if (!executionID.length) return CopyUTF8(@"{\"error\":\"Python execution requires a job ID.\"}");
    std::shared_ptr<std::atomic<bool>> cancellation;
    {
        std::lock_guard<std::mutex> guard(cancellationMutex);
        auto found = cancellationFlags.find(executionID.UTF8String);
        if (found != cancellationFlags.end()) cancellation = found->second;
    }
    if (!cancellation) return CopyUTF8(@"{\"error\":\"Python job cancellation identity is not registered.\"}");
    NSURL *bootstrapURL = [NSBundle.mainBundle URLForResource:@"HanlinPythonExecution" withExtension:@"py"];
    NSString *bootstrap = bootstrapURL ? [NSString stringWithContentsOfURL:bootstrapURL encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!bootstrap.length) return CopyUTF8(@"{\"error\":\"The embedded Python execution resource is missing.\"}");

    PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *globals = PyDict_New();
    PyObject *cancellationFunction = HanlinPythonCancellation::makeFunction(cancellation);
    if (!globals || !cancellationFunction || PyDict_SetItemString(globals, "_hanlin_is_cancelled", cancellationFunction) != 0) {
        Py_XDECREF(cancellationFunction);
        Py_XDECREF(globals);
        PyErr_Clear();
        PyGILState_Release(gil);
        return CopyUTF8(@"{\"error\":\"Unable to allocate the Python job context.\"}");
    }
    Py_DECREF(cancellationFunction);
    PyObject *requestString = PyUnicode_DecodeUTF8(requestJSON, strlen(requestJSON), "strict");
    if (requestString) PyDict_SetItemString(globals, "__hanlin_request_json", requestString);
    Py_XDECREF(requestString);
    PyObject *builtins = PyEval_GetBuiltins();
    if (builtins) {
        PyDict_SetItemString(globals, "__builtins__", builtins);
    } else {
        PyObject *builtinsModule = PyImport_ImportModule("builtins");
        if (builtinsModule) {
            PyDict_SetItemString(globals, "__builtins__", PyModule_GetDict(builtinsModule));
            Py_DECREF(builtinsModule);
        }
    }
    PyObject *executed = PyRun_StringFlags(bootstrap.UTF8String, Py_file_input, globals, globals, nullptr);
    NSString *result = nil;
    if (executed) {
        Py_DECREF(executed);
        PyObject *value = PyDict_GetItemString(globals, "_hanlin_response_json");
        if (value && PyUnicode_Check(value)) result = [NSString stringWithUTF8String:PyUnicode_AsUTF8(value)];
    } else {
        PyObject *pvalue = PyErr_GetRaisedException();
        NSString *errDesc = @"Unknown Python error";
        if (pvalue) {
            PyObject *strObj = PyObject_Str(pvalue);
            if (strObj) {
                const char *utf8 = PyUnicode_AsUTF8(strObj);
                if (utf8) errDesc = [NSString stringWithUTF8String:utf8];
                Py_DECREF(strObj);
            }
        }
        NSDictionary *errDict = @{ @"error": [NSString stringWithFormat:@"Embedded Python execution failed: %@", errDesc] };
        NSData *errData = [NSJSONSerialization dataWithJSONObject:errDict options:0 error:nil];
        if (errData) result = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
        Py_XDECREF(pvalue);
    }
    Py_DECREF(globals);
    PyGILState_Release(gil);
    return CopyUTF8(result ?: @"{\"error\":\"Embedded Python execution failed before producing a result.\"}");
}

void HanlinPythonFree(char *value) {
    free(value);
}
