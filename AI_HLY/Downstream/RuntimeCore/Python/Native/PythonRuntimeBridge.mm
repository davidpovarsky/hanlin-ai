#include "PythonRuntimeBridge.h"
#include <Foundation/Foundation.h>
#include <Python/Python.h>
#include <mutex>

static std::once_flag initializationFlag;
static NSString *initializationError = nil;

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
        NSString *resources = NSBundle.mainBundle.resourcePath;
        NSString *pythonHome = [resources stringByAppendingPathComponent:@"python"];
        setenv("PYTHONHOME", pythonHome.UTF8String, 1);
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1);
        setenv("PYTHONUTF8", "1", 1);

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

    NSString *source = [request[@"source"] isKindOfClass:NSString.class] ? request[@"source"] : @"";
    NSString *workspace = [request[@"workspace"] isKindOfClass:NSString.class] ? request[@"workspace"] : @"";
    NSString *packages = [request[@"packages"] isKindOfClass:NSString.class] ? request[@"packages"] : @"";
    NSArray *arguments = [request[@"arguments"] isKindOfClass:NSArray.class] ? request[@"arguments"] : @[];
    NSDictionary *environment = [request[@"environment"] isKindOfClass:NSDictionary.class] ? request[@"environment"] : @{};
    double timeout = [request[@"timeoutSeconds"] doubleValue];

    NSData *argumentsData = [NSJSONSerialization dataWithJSONObject:arguments options:0 error:nil];
    NSData *environmentData = [NSJSONSerialization dataWithJSONObject:environment options:0 error:nil];
    NSString *source64 = [[source dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *workspace64 = [[workspace dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *packages64 = [[packages dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSString *arguments64 = [argumentsData base64EncodedStringWithOptions:0];
    NSString *environment64 = [environmentData base64EncodedStringWithOptions:0];

    NSString *bootstrapFormat = [NSString stringWithUTF8String:R"PY(
import base64, contextlib, io, json, os, site, sys, time, traceback
_source = base64.b64decode('%@').decode('utf-8')
_workspace = base64.b64decode('%@').decode('utf-8')
_packages = base64.b64decode('%@').decode('utf-8')
_arguments = json.loads(base64.b64decode('%@'))
_environment = json.loads(base64.b64decode('%@'))
_deadline = time.monotonic() + %.6f
_stdout, _stderr = io.StringIO(), io.StringIO()
_old_cwd, _old_argv, _old_env, _old_path = os.getcwd(), list(sys.argv), dict(os.environ), list(sys.path)
def _hanlin_trace(frame, event, arg):
    if time.monotonic() > _deadline:
        raise TimeoutError('Python execution timed out.')
    return _hanlin_trace
try:
    os.chdir(_workspace)
    os.environ.update({str(k): str(v) for k, v in _environment.items()})
    sys.argv = ['<hanlin>', *[str(value) for value in _arguments]]
    if os.path.isdir(_packages):
        for _entry in sorted(os.listdir(_packages)):
            _candidate = os.path.join(_packages, _entry)
            if os.path.isdir(_candidate): site.addsitedir(_candidate)
    _globals = {'__name__': '__main__', '__file__': '<hanlin>'}
    sys.settrace(_hanlin_trace)
    with contextlib.redirect_stdout(_stdout), contextlib.redirect_stderr(_stderr):
        exec(compile(_source, '<hanlin>', 'exec'), _globals, _globals)
    _value = _globals.get('__hanlin_result__')
    try: json.dumps(_value)
    except (TypeError, ValueError): _value = str(_value)
    _hanlin_response = {'stdout': _stdout.getvalue(), 'stderr': _stderr.getvalue(), 'value': _value, 'exitCode': 0, 'didTimeOut': False}
except BaseException as _error:
    _hanlin_response = {'stdout': _stdout.getvalue(), 'stderr': _stderr.getvalue() + traceback.format_exc(), 'value': None, 'exitCode': 1, 'didTimeOut': isinstance(_error, TimeoutError)}
finally:
    sys.settrace(None)
    os.chdir(_old_cwd)
    sys.argv[:] = _old_argv
    os.environ.clear(); os.environ.update(_old_env)
    sys.path[:] = _old_path
_hanlin_response_json = json.dumps(_hanlin_response, ensure_ascii=False)
)PY"];
    NSString *bootstrap = [NSString stringWithFormat:bootstrapFormat, source64, workspace64, packages64, arguments64, environment64, MAX(1.0, timeout)];

    PyGILState_STATE gil = PyGILState_Ensure();
    PyObject *globals = PyDict_New();
    PyDict_SetItemString(globals, "__builtins__", PyEval_GetBuiltins());
    PyObject *executed = PyRun_StringFlags(bootstrap.UTF8String, Py_file_input, globals, globals, nullptr);
    NSString *result = nil;
    if (executed) {
        Py_DECREF(executed);
        PyObject *value = PyDict_GetItemString(globals, "_hanlin_response_json");
        if (value && PyUnicode_Check(value)) result = [NSString stringWithUTF8String:PyUnicode_AsUTF8(value)];
    } else {
        PyErr_Clear();
    }
    Py_DECREF(globals);
    PyGILState_Release(gil);
    return CopyUTF8(result ?: @"{\"error\":\"Embedded Python execution failed before producing a result.\"}");
}

void HanlinPythonFree(char *value) {
    free(value);
}
