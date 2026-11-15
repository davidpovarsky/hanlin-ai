#pragma once

#include "Pipeline.h"
#include <chrono>
#include <filesystem>

namespace HanlinDual {

inline void writeExclusive(const std::string& path, llvm::StringRef bytes) {
    std::error_code error;
    llvm::raw_fd_ostream file(path, error, llvm::sys::fs::CD_CreateNew);
    if (error) throw std::runtime_error("Cannot exclusively create dual output: " + path);
    file << bytes;
    file.close();
    if (file.has_error()) throw std::runtime_error("Dual output write failed: " + path);
}

inline void verifyBoundFiles(const llvm::json::Object& request) {
    const auto* files = request.getArray("boundFiles");
    if (!files || files->empty()) throw std::runtime_error("Dual request has no bound physical inputs");
    for (const auto& entry : *files) {
        const auto* file = entry.getAsObject();
        if (!file || hanlinSHA(hanlinRead(hanlinString(*file, "path"))) != hanlinString(*file, "sha256"))
            throw std::runtime_error("Dual bound physical input drift");
    }
}

inline std::vector<std::string> objcArguments(const std::vector<std::string>& cpp, const std::string& standardLibrary) {
    std::vector<std::string> result;
    for (size_t n = 0; n < cpp.size(); ++n) {
        if (cpp[n] == "-x" || cpp[n] == "-std") {
            if (++n == cpp.size()) throw std::runtime_error("Incomplete dual grammar argument");
        } else if (!llvm::StringRef(cpp[n]).starts_with("-std=")) result.push_back(cpp[n]);
    }
    // ObjC does not add the C++ standard-library directory implicitly. Add the
    // same physical directory, then require the actual ordered search context
    // to be byte-identical to A. No full-pass argument or input is removed.
    result.insert(result.end(), {"-x", "objective-c", "-std=gnu17", "-isystem", standardLibrary});
    return result;
}

inline llvm::json::Array outputManifest(const std::string& stage) {
    namespace fs = std::filesystem;
    std::vector<fs::path> paths;
    for (const auto& entry : fs::recursive_directory_iterator(stage)) {
        if (entry.is_symlink()) throw std::runtime_error("Symlink in dual output transaction");
        if (entry.is_regular_file()) paths.push_back(entry.path());
    }
    std::sort(paths.begin(), paths.end());
    llvm::json::Array files;
    for (const auto& path : paths)
        files.push_back(llvm::json::Object{{"path", path.lexically_relative(stage).generic_string()},
            {"sha256", hanlinSHA(hanlinRead(path.string()))}, {"bytes", static_cast<int64_t>(fs::file_size(path))}});
    return files;
}

inline int generate(const std::string& requestPath, const std::vector<std::string>& fullArguments,
                    const std::string& fullCode, const std::string& context,
                    Meta::ModulesBlacklist& blacklist, llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem> files) {
    namespace fs = std::filesystem;
    const auto started = std::chrono::steady_clock::now();
    const auto requestBytes = hanlinRead(requestPath);
    auto parsed = llvm::json::parse(requestBytes);
    if (!parsed) { llvm::consumeError(parsed.takeError()); throw std::runtime_error("Invalid dual request JSON"); }
    const auto* request = parsed->getAsObject();
    if (!request || request->getInteger("schemaVersion") != 2 || request->getInteger("mergePolicyVersion") != 3 ||
        request->getString("mode") != "retained-dual-grammar") throw std::runtime_error("Unsupported dual request contract");
    verifyBoundFiles(*request);
    if (hanlinString(*request, "contextSHA256") != hanlinSHA(context) ||
        hanlinString(*request, "fullRootSHA256") != hanlinSHA(fullCode))
        throw std::runtime_error("Actual full grammar root/context drift");
    const auto objcPath = hanlinString(*request, "objcRoot");
    const auto objcCode = hanlinRead(objcPath);
    if (hanlinString(*request, "objcRootSHA256") != hanlinSHA(objcCode))
        throw std::runtime_error("Canonical ObjC root drift");
    const auto alternateArguments = objcArguments(fullArguments, hanlinString(*request, "standardLibraryDirectory"));
    const std::string binary = cla_outputBinFile.getValue(), yaml = cla_outputYamlFolder.getValue();
    const std::string types = cla_outputDtsFolder.getValue(), umbrella = cla_outputUmbrellaHeaderFile.getValue();
    if (binary.empty() || !fs::path(binary).is_absolute() || !cla_outputModuleMapsFolder.empty())
        throw std::runtime_error("Dual metadata requires an absolute binary output and no module-map output");
    const auto receipt = binary + ".dual-grammar.json";
    const auto stage = binary + ".dual-stage-" + hanlinSHA(requestBytes).substr(0, 24);
    if (fs::exists(stage) || !fs::create_directory(stage)) throw std::runtime_error("Dual transaction output already exists");
    // Old binaries are never accepted by this operation: the new receipt is
    // bound to this request and published only after every new output succeeds.
    for (const auto& directory : {yaml, types})
        if (!directory.empty() && (!fs::path(directory).is_absolute() ||
            (fs::exists(directory) && (!fs::is_directory(directory) || !fs::is_empty(directory)))))
            throw std::runtime_error("Dual directory output is not exclusively writable");
    if (hanlinWriterEntries) throw std::runtime_error("A writer ran before dual parse/merge");
    Pipeline pipeline(fullCode, fullArguments, objcCode, alternateArguments, blacklist, files, request);
    pipeline.merge();
    const auto stageBinary = stage + "/metadata.bin";
    cla_outputBinFile.setValue(stageBinary);
    cla_outputYamlFolder.setValue(yaml.empty() ? "" : stage + "/yaml");
    cla_outputDtsFolder.setValue(types.empty() ? "" : stage + "/types");
    pipeline.emit();
    auto lifetime = pipeline.lifetime();
    if (!fs::is_regular_file(stageBinary) || fs::file_size(stageBinary) == 0)
        throw std::runtime_error("Original dual serializer produced no binary");
    if (!umbrella.empty()) writeExclusive(stage + "/umbrella.h", fullCode);
    verifyBoundFiles(*request);
    llvm::json::Object result{{"schemaVersion", 2}, {"status", "COMPLETE"}, {"mode", "retained-dual-grammar"},
        {"mergePolicyVersion", 3}, {"requestSHA256", hanlinSHA(requestBytes)}, {"contextSHA256", hanlinSHA(context)},
        {"proof", pipeline.proofReceipt()}, {"lifetime", std::move(lifetime)},
        {"metadataSHA256", hanlinSHA(hanlinRead(stageBinary))}, {"outputs", outputManifest(stage)},
        {"destinations", llvm::json::Object{{"binary", binary}, {"yaml", yaml}, {"types", types}, {"umbrella", umbrella}}},
        {"cacheReuse", "DISABLED"}, {"consumerEntries", static_cast<int64_t>(hanlinConsumerEntries)},
        {"writerEntries", static_cast<int64_t>(hanlinWriterEntries)}, {"peakRSSBytes", peakResidentBytes()},
        {"seconds", std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count()},
        {"runtimeAcceptance", "NOT_ESTABLISHED"}};
    llvm::json::Value finalReceipt(std::move(result));
    auto* statistics = finalReceipt.getAsObject();
    (*statistics)["secondsMeasurement"] = "start_to_final_receipt_render_begin";
    (*statistics)["peakRSSMeasurement"] = "maximum_through_complete_receipt_render";
    std::string receiptBytes;
    for (unsigned render = 0; ; ++render) {
        const auto observedPeak = peakResidentBytes();
        (*statistics)["peakRSSBytes"] = observedPeak;
        (*statistics)["seconds"] = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
        receiptBytes = llvm::formatv("{0:2}\n", finalReceipt).str();
        requireResidentBudget("complete receipt construction before publication");
        if (peakResidentBytes() == observedPeak) break;
        if (render == 3) throw std::runtime_error("Receipt RSS accounting did not stabilize within bounded pure renders");
    }
    writeExclusive(stage + "/receipt.json", receiptBytes);
    requireResidentBudget("all staged outputs before publication");
    // Each rename is atomic. Publish the receipt last; consumers must verify
    // its complete bound identity and all hashes, never accept a partial set.
    if (!yaml.empty()) fs::rename(stage + "/yaml", yaml);
    if (!types.empty()) fs::rename(stage + "/types", types);
    if (!umbrella.empty()) fs::rename(stage + "/umbrella.h", umbrella);
    fs::rename(stageBinary, binary);
    fs::rename(stage + "/receipt.json", receipt);
    fs::remove(stage); // Only the now-empty transaction directory created here.
    return 0;
}

} // namespace HanlinDual
