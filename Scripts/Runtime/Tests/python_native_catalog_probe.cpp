#include "HanlinPythonNativeExtensions.mm"
#include <chrono>
#include <future>
#include <iostream>
#include <stdexcept>
#include <string>

static void require(bool value, const char *message) {
    if (!value) throw std::runtime_error(message);
}
static std::string snapshot() {
    char *value = HanlinPythonNativeExtensionCatalogJSON();
    require(value != nullptr, "Catalog allocation failed");
    std::string result(value);
    std::free(value);
    return result;
}
int main(int argc, char **argv) {
    try {
        require(argc == 2, "Expected the actual Python home");
        require(!Py_IsInitialized(), "Interpreter already started before catalog test");
        std::cout << "BEFORE\t" << snapshot() << std::endl;
        require(!Py_IsInitialized(), "A read-only catalog initialized Python");
        require(HanlinPythonRegisterBundledExtensions() == 0, "Real inittab registration failed");
        std::cout << "REGISTERED\t" << snapshot() << std::endl;
        require(!Py_IsInitialized(), "Registration initialized Python");
        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.write_bytecode = 0;
        PyStatus status = PyConfig_SetBytesString(&config, &config.home, argv[1]);
        if (!PyStatus_Exception(status)) status = Py_InitializeFromConfig(&config);
        PyConfig_Clear(&config);
        require(!PyStatus_Exception(status), "Actual embedded test interpreter initialization failed");
        PyObject *module = PyImport_ImportModule("_hanlin_native");
        if (!module) PyErr_Print();
        require(module != nullptr, "Actual compiled builtin import failed");
        PyObject *challenge = PyObject_CallMethod(module, "challenge", "s", "actual-native-catalog-nonce-42");
        require(challenge != nullptr, "Actual compiled native challenge failed");
        PyObject *nonce = PyDict_GetItemString(challenge, "nonce");
        require(nonce && PyUnicode_CompareWithASCIIString(nonce, "actual-native-catalog-nonce-42") == 0,
            "The actual compiled native nonce did not survive");
        Py_DECREF(challenge);
        // Main owns the GIL here. A read-only getter must finish on another
        // native thread without entering Python or waiting for its job queue.
        auto concurrent = std::async(std::launch::async, snapshot);
        require(concurrent.wait_for(std::chrono::seconds(3)) == std::future_status::ready,
            "Catalog blocked on the interpreter/GIL");
        const std::string observed = concurrent.get();
        std::cout << "IMPORTED\t" << observed << std::endl;
        PyObject *json = PyImport_ImportModule("json");
        require(json != nullptr, "Actual stdlib JSON import failed");
        PyObject *decoded = PyObject_CallMethod(json, "loads", "s", observed.c_str());
        PyObject *registry = PyObject_CallMethod(module, "registry", nullptr);
        require(decoded && registry && PyObject_RichCompareBool(decoded, registry, Py_EQ) == 1,
            "Host and Python registries disagree on the actual linked provider table");
        Py_DECREF(decoded); Py_DECREF(registry); Py_DECREF(json); Py_DECREF(module);
        require(HanlinPythonRegisterBundledExtensions() == 0, "Registration was not idempotent");
        require(Py_FinalizeEx() == 0, "Actual test interpreter finalization failed");
        std::cout << "FINALIZED\t" << snapshot() << std::endl;
        require(!Py_IsInitialized(), "Catalog restarted a finalized interpreter");
        std::cout << "ACTUAL_NATIVE_CATALOG_NONCE_GIL_AND_LIFECYCLE_PASSED" << std::endl;
        return 0;
    } catch (const std::exception &failure) {
        std::cerr << failure.what() << std::endl;
        return 1;
    }
}
