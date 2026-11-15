#include <Python.h>
#include "PythonThreadOwnership.hpp"

static PyObject *closeOwner(PyObject *capsule, PyObject *) {
    auto owner = static_cast<HanlinPythonThreads::Owner *>(PyCapsule_GetPointer(capsule, HanlinPythonThreads::capsuleName));
    if (!owner) return nullptr;
    (*owner)->active.store(false);
    Py_RETURN_NONE;
}
static PyObject *make(PyObject *, PyObject *) {
    HanlinPythonThreads::Owner owner;
    try { owner = std::make_shared<HanlinPythonThreads::State>(); }
    catch (const std::bad_alloc &) { return PyErr_NoMemory(); }
    PyObject *counter = HanlinPythonThreads::makeCounter(owner);
    if (!counter) return nullptr;
    static PyMethodDef method = {"close", closeOwner, METH_NOARGS, nullptr};
    PyObject *close = PyCFunction_NewEx(&method, PyCFunction_GetSelf(counter), nullptr);
    if (!close) { Py_DECREF(counter); return nullptr; }
    PyObject *pair = PyTuple_Pack(2, counter, close);
    Py_DECREF(counter);
    Py_DECREF(close);
    return pair;
}
static PyMethodDef methods[] = {{"make", make, METH_NOARGS, nullptr}, {nullptr,nullptr,0,nullptr}};
static PyModuleDef module = {PyModuleDef_HEAD_INIT,"_thread_owner_probe",nullptr,-1,methods};
PyMODINIT_FUNC PyInit__thread_owner_probe(void) { return PyModule_Create(&module); }
