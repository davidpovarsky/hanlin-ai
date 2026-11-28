#include <Python.h>
#include "PythonCancellationContext.hpp"
static std::weak_ptr<std::atomic<bool>> observer;
static PyObject *make(PyObject *, PyObject *) {
    auto flag = std::make_shared<std::atomic<bool>>(false);
    observer = flag;
    return HanlinPythonCancellation::makeFunction(flag);
}
static PyObject *alive(PyObject *, PyObject *) { return PyBool_FromLong(!observer.expired()); }
static PyObject *cancel(PyObject *, PyObject *) {
    auto flag = observer.lock();
    if (!flag) { PyErr_SetString(PyExc_RuntimeError, "Cancellation flag expired"); return nullptr; }
    flag->store(true); Py_RETURN_NONE;
}
static PyObject *preserve_error(PyObject *, PyObject *) {
    auto flag = std::make_shared<std::atomic<bool>>(false);
    PyObject *callback = HanlinPythonCancellation::makeFunction(flag);
    if (!callback) return nullptr;
    PyErr_SetString(PyExc_RuntimeError, "original exception preserved");
    Py_DECREF(callback);
    return nullptr;
}
static PyMethodDef methods[] = {{"make",make,METH_NOARGS,nullptr},{"alive",alive,METH_NOARGS,nullptr},{"cancel",cancel,METH_NOARGS,nullptr},{"preserve_error",preserve_error,METH_NOARGS,nullptr},{nullptr,nullptr,0,nullptr}};
static PyModuleDef module = {PyModuleDef_HEAD_INIT,"_cancellation_probe",nullptr,-1,methods};
PyMODINIT_FUNC PyInit__cancellation_probe(void) { return PyModule_Create(&module); }
