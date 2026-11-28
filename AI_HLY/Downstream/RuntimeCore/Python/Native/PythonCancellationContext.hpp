#pragma once

// Include the target's Python.h before this header. The same ownership code is
// exercised against portable CPython and the app's actual Python framework.
#include <atomic>
#include <memory>
#include <new>

namespace HanlinPythonCancellation {
using Flag = std::shared_ptr<std::atomic<bool>>;
inline constexpr const char *capsuleName = "hanlin.job.cancellation";

inline void destroy(PyObject *capsule) {
    PyObject *saved = PyErr_GetRaisedException();
    auto owner = static_cast<Flag *>(PyCapsule_GetPointer(capsule, capsuleName));
    delete owner;
    PyErr_SetRaisedException(saved);
}

inline PyObject *requested(PyObject *capsule, PyObject *) {
    auto owner = static_cast<Flag *>(PyCapsule_GetPointer(capsule, capsuleName));
    if (!owner) return nullptr;
    return PyBool_FromLong((*owner)->load());
}

inline PyObject *makeFunction(const Flag &flag) {
    // Python may retain sys.gettrace() or this callback after the job registry
    // releases its flag. The capsule must own a shared reference, not flag.get().
    auto owner = new (std::nothrow) Flag(flag);
    if (!owner) return PyErr_NoMemory();
    PyObject *capsule = PyCapsule_New(owner, capsuleName, destroy);
    if (!capsule) { delete owner; return nullptr; }
    static PyMethodDef method = {"_hanlin_is_cancelled", requested, METH_NOARGS, nullptr};
    PyObject *function = PyCFunction_NewEx(&method, capsule, nullptr);
    Py_DECREF(capsule);
    return function;
}
}
