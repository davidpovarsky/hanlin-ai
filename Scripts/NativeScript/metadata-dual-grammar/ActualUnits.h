#pragma once

// Included after the original, adapted MetaGenerationConsumer declaration.
#include <clang/Frontend/ASTUnit.h>
#include <clang/Lex/DirectoryLookup.h>
#include <clang/Lex/PreprocessorOptions.h>
#include <clang/Tooling/Tooling.h>
#include <sys/resource.h>

namespace HanlinDual {

inline int64_t peakResidentBytes() {
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) != 0) throw std::runtime_error("Cannot measure native metadata RSS");
    return usage.ru_maxrss; // This candidate is explicitly macOS: ru_maxrss is bytes.
}

inline llvm::json::Array searchDirectories(clang::ASTUnit& ast) {
    llvm::json::Array directories;
    auto& search = ast.getPreprocessor().getHeaderSearchInfo();
    for (auto item = search.search_dir_begin(); item != search.search_dir_end(); ++item) {
        if (item->isHeaderMap()) throw std::runtime_error("Unproven header-map search context in dual grammar");
        directories.push_back(llvm::json::Object{{"path", item->getName().str()},
            {"framework", item->isFramework()}, {"characteristic", static_cast<int64_t>(item->getDirCharacteristic())}});
    }
    return directories;
}

inline llvm::json::Object dependencies(clang::ASTUnit& ast) {
    auto& manager = ast.getSourceManager();
    llvm::json::Object inputs;
    for (auto entry = manager.fileinfo_begin(); entry != manager.fileinfo_end(); ++entry) {
        auto id = manager.translateFile(entry->first);
        if (id.isInvalid() || id == manager.getMainFileID()) continue;
        auto path = entry->first.getFileEntry().tryGetRealPathName().str();
        if (path.empty()) throw std::runtime_error("Actual AST dependency has no physical identity");
        const auto buffer = manager.getBufferData(id);
        if (buffer != hanlinRead(path)) throw std::runtime_error("Actual AST dependency bytes drifted: " + path);
        inputs[path] = hanlinSHA(buffer);
    }
    return inputs;
}

class ActualUnit {
    // Destruction is reverse declaration order: factory/consumer first, then AST.
    std::unique_ptr<clang::ASTUnit> ast;
    std::unique_ptr<MetaGenerationConsumer> consumer;

public:
    llvm::json::Object receipt;

    ActualUnit(const std::string& code, const std::vector<std::string>& arguments,
               Meta::ModulesBlacklist& blacklist, llvm::IntrusiveRefCntPtr<llvm::vfs::FileSystem> fs) {
        const auto beforeRSS = peakResidentBytes();
        if (beforeRSS > 4LL * 1024 * 1024 * 1024) throw std::runtime_error("Dual metadata RSS budget exceeded before AST");
        if (beforeRSS * 2 + 128LL * 1024 * 1024 > 4LL * 1024 * 1024 * 1024)
            throw std::runtime_error("Insufficient measured RSS reserve for the next retained AST");
        ast = clang::tooling::buildASTFromCodeWithArgs(code, arguments, "umbrella.h", "objc-metadata-generator",
            std::make_shared<clang::PCHContainerOperations>(), clang::tooling::getClangStripDependencyFileAdjuster(),
            clang::tooling::FileContentMappings(), nullptr, fs);
        if (!ast || ast->getDiagnostics().hasErrorOccurred()) throw std::runtime_error("Actual dual-grammar AST parse failed");
        if (ast->isMainFileAST() || ast->getSourceManager().loaded_sloc_entry_size() != 0 ||
            !ast->getPreprocessorOpts().ImplicitPCHInclude.empty() || ast->getLangOpts().Modules)
            throw std::runtime_error("Serialized AST/module inputs are prohibited in dual grammar");
        if (peakResidentBytes() > 4LL * 1024 * 1024 * 1024) throw std::runtime_error("Dual metadata RSS budget exceeded after AST");
        receipt = llvm::json::Object{{"compiler", clang::getClangFullVersion()},
            {"language", ast->getLangOpts().CPlusPlus ? "objective-c++" : "objective-c"},
            {"target", ast->getASTContext().getTargetInfo().getTriple().str()},
            {"resourceDirectory", ast->getHeaderSearchOpts().ResourceDir},
            {"rootSHA256", hanlinSHA(code)}, {"peakRSSBeforeAST", beforeRSS},
            {"peakRSSAfterAST", peakResidentBytes()}, {"peakRSSBudget", 4LL * 1024 * 1024 * 1024},
            {"actualSearchDirectories", searchDirectories(*ast)}, {"sourceDependencies", dependencies(*ast)}};
        llvm::json::Array argv;
        for (const auto& argument : arguments) argv.push_back(argument);
        receipt["arguments"] = std::move(argv);
        consumer = std::make_unique<MetaGenerationConsumer>(ast->getSourceManager(),
            ast->getPreprocessor().getHeaderSearchInfo(), blacklist);
        consumer->hanlinSetCollectOnly();
        ++hanlinConsumerEntries;
        consumer->HandleTranslationUnit(ast->getASTContext());
        receipt["collectedModels"] = static_cast<int64_t>(consumer->hanlinMetas().size());
        receipt["sourceDependencies"] = dependencies(*ast); // Includes ownership module maps read by the original collector.
        receipt["peakRSSAfterModels"] = peakResidentBytes();
        if (peakResidentBytes() > 4LL * 1024 * 1024 * 1024) throw std::runtime_error("Dual metadata RSS budget exceeded after models");
    }

    std::list<Meta::Meta*>& models() { return consumer->hanlinMetas(); }
    MetaGenerationConsumer& producer() { return *consumer; }
    clang::ASTContext& context() { return ast->getASTContext(); }
    clang::ASTUnit& unit() { return *ast; }
};

} // namespace HanlinDual
