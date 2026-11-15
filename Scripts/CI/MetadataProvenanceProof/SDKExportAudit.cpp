#include "../../NativeScript/metadata-dual-grammar/SDKExportClosure.h"
using namespace llvm;
using namespace llvm::MachO;
using namespace HanlinDual;

int main(int argc, char** argv) {
    if (argc != 7) return 2;
    const std::string sdk = argv[1], stub = argv[2], targetText = argv[3], c = argv[4], cpp = argv[5], output = argv[6];
    auto parsedTarget = Target::create(targetText);
    if (!parsedTarget) { errs() << toString(parsedTarget.takeError()); return 2; }
    const auto target = *parsedTarget;
    json::Array cases;
    bool passed = true;
    const auto run = [&](StringRef name, StringRef expected, auto mutation, StringRef requestedC = StringRef()) {
        json::Object receipt{{"case", name.str()}, {"expected", expected.str()}};
        try {
            SDKExportClosure closure(sdk, stub);
            Target selected = target;
            mutation(closure, selected);
            auto proof = closure.choose(selected, requestedC.empty() ? StringRef(c) : requestedC, cpp);
            receipt["decision"] = std::move(proof);
            receipt["status"] = expected == "PASS" ? "EXECUTED_PASS" : "FAILED";
        } catch (const std::exception& error) {
            receipt["reason"] = std::string(error.what());
            receipt["status"] = StringRef(error.what()).starts_with(expected) ? "EXECUTED_PASS" : "FAILED";
        }
        if (receipt.getString("status") != "EXECUTED_PASS") passed = false;
        cases.push_back(std::move(receipt));
    };
    run("actual-sdk-single-C-export", "PASS", [](auto&, auto&) {});
    run("genuine-both-bindings-exported", "CPP_EXPORT_EXISTS", [&](auto& closure, auto& selected) {
        closure.ownerOf(c, selected).addSymbol(EncodeKind::GlobalSymbol, cpp, selected);
    });
    run("ambiguous-C-export-owner", "AMBIGUOUS_C_EXPORT", [&](auto& closure, auto& selected) {
        closure.root->addSymbol(EncodeKind::GlobalSymbol, c, selected);
    });
    run("missing-C-export", "MISSING_C_EXPORT", [](auto&, auto&) {}, c + "_not_exported");
    run("wrong-target-platform", "TARGET_MISMATCH", [&](auto&, auto& selected) {
        auto device = Target::create("arm64-ios");
        if (!device) throw std::runtime_error(toString(device.takeError()));
        selected = *device;
    });
    run("unresolved-target-reexport", "MISSING_EXPORT_FILE", [&](auto& closure, auto& selected) {
        closure.root->addReexportedLibrary("/System/Library/Frameworks/HanlinMissing.framework/HanlinMissing", selected);
    });
    const auto targetCase = [&](StringRef name, StringRef a, StringRef b, bool expected) {
        const bool observed = sameBoundTargetTriple(a, b);
        const bool valid = observed == expected;
        if (!valid) passed = false;
        cases.push_back(json::Object{{"case", name.str()}, {"left", a.str()}, {"right", b.str()},
            {"expectedEquivalent", expected}, {"observedEquivalent", observed}, {"status", valid ? "EXECUTED_PASS" : "FAILED"}});
    };
    targetCase("bound-target-explicit-zero-components", "arm64-apple-ios27.2-simulator", "arm64-apple-ios27.2.0-simulator", true);
    targetCase("different-deployment-version-rejected", "arm64-apple-ios27.2-simulator", "arm64-apple-ios27.3.0-simulator", false);
    targetCase("different-target-environment-rejected", "arm64-apple-ios27.2-simulator", "arm64-apple-ios27.2.0", false);
    std::error_code error;
    raw_fd_ostream file(output, error);
    if (error) return 2;
    file << formatv("{0:2}\n", json::Value(json::Object{{"status", passed ? "EXECUTED_PASS" : "FAILED"},
        {"scope", "NATIVE_EXPORT_AUTHORITY_PROTOTYPE_ONLY"}, {"target", targetText}, {"CBinding", c}, {"CPPBinding", cpp},
        {"cases", std::move(cases)}, {"metadataProducerExecution", "NOT_RUN"}, {"productionDefault", "LEGACY_UNCHANGED"}}));
    return passed ? 0 : 1;
}
