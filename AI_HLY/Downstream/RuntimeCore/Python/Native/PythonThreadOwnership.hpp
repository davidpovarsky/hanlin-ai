#pragma once

// Include Python.h first. Access is confined to the serialized Python executor
// while holding the GIL. Count actual CPython thread states, including _thread
// aliases and daemon threads that threading.enumerate()/join() cannot own.
#include <atomic>
#include <cstdint>
#include <memory>
#include <new>
#include <unordered_set>

namespace HanlinPythonThreads {
struct State {
    PyInterpreterState *interpreter;
    uint64_t executor;
    std::unordered_set<uint64_t> baseline;
    std::atomic<bool> active{true};

    State() : interpreter(PyThreadState_GetInterpreter(PyThreadState_Get())),
              executor(PyThreadState_GetID(PyThreadState_Get())) {
        for (auto thread = PyInterpreterState_ThreadHead(interpreter); thread; thread = PyThreadState_Next(thread))
            baseline.insert(PyThreadState_GetID(thread));
    }
};
using Owner = std::shared_ptr<State>;
inline constexpr const char *capsuleName = "hanlin.job.python-threads";

inline void destroy(PyObject *capsule) {
    PyObject *saved = PyErr_GetRaisedException();
    delete static_cast<Owner *>(PyCapsule_GetPointer(capsule, capsuleName));
    PyErr_SetRaisedException(saved);
}

inline PyObject *count(PyObject *capsule, PyObject *) {
    auto owner = static_cast<Owner *>(PyCapsule_GetPointer(capsule, capsuleName));
    if (!owner) return nullptr;
    if (!(*owner)->active.load() || PyThreadState_GetID(PyThreadState_Get()) != (*owner)->executor) {
        PyErr_SetString(PyExc_RuntimeError, "Python thread ownership is available only to its active job executor.");
        return nullptr;
    }
    size_t pending = 0;
    for (auto thread = PyInterpreterState_ThreadHead((*owner)->interpreter); thread; thread = PyThreadState_Next(thread))
        if (!(*owner)->baseline.count(PyThreadState_GetID(thread))) ++pending;
    return PyLong_FromSize_t(pending);
}

inline PyObject *makeCounter(const Owner &state) {
    auto owner = new (std::nothrow) Owner(state);
    if (!owner) return PyErr_NoMemory();
    PyObject *capsule = PyCapsule_New(owner, capsuleName, destroy);
    if (!capsule) { delete owner; return nullptr; }
    static PyMethodDef method = {"_hanlin_owned_thread_count", count, METH_NOARGS, nullptr};
    PyObject *function = PyCFunction_NewEx(&method, capsule, nullptr);
    Py_DECREF(capsule);
    return function;
}
}
