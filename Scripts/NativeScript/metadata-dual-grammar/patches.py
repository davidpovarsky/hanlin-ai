"""Expose the original collector/emitter for retained, real dual ASTs."""


def apply(text, replace_once):
    first = text.index("class MetaGenerationConsumer :")
    last = text.index("class MetaGenerationFrontendAction :", first)
    consumer = text[first:last]
    emission_start = consumer.index("        // Log statistic for parsed Meta objects")
    emission_end = consumer.index("\n    }\n\nprivate:", emission_start)
    emission = consumer[emission_start:emission_end]
    consumer = consumer[:emission_start] + """        _hanlinMetas = &metaContainer;
        if (!_hanlinCollectOnly) hanlinEmitMetadata(metaContainer, metasByModules);
""" + consumer[emission_end:]
    consumer = replace_once(consumer, "    virtual void HandleTranslationUnit", """    void hanlinSetCollectOnly() { _hanlinCollectOnly = true; }
    std::list<Meta::Meta*>& hanlinMetas() {
        if (!_hanlinMetas) throw std::runtime_error("Actual AST models were not collected");
        return *_hanlinMetas;
    }
    Meta::MetaFactory& hanlinFactory() { return _visitor.getMetaFactory(); }
    void hanlinEmitMetadata(std::list<Meta::Meta*>& metaContainer,
        Meta::ResolveGlobalNamesCollisionsFilter::MetasByModules& metasByModules) {
        llvm::SmallVector<clang::Module*, 64> modules;
        _headerSearch.collectAllModules(modules);
""" + emission + "\n    }\n\n    virtual void HandleTranslationUnit")
    consumer = replace_once(consumer, "        // Preserve actual parser errors for runToolOnCodeWithArgs.",
        "        if (Context.getDiagnostics().hasErrorOccurred()) throw std::runtime_error(\"Actual AST parse has errors\");")
    consumer = replace_once(consumer, "private:\n    clang::HeaderSearch& _headerSearch;",
        "private:\n    bool _hanlinCollectOnly = false;\n    std::list<Meta::Meta*>* _hanlinMetas = nullptr;\n    clang::HeaderSearch& _headerSearch;")
    return text[:first] + consumer + text[last:]


def patch_factories(header, source, replace_once):
    header = replace_once(header, "    void validate(Meta* meta);", """    void validate(Meta* meta);
    void hanlinSetPeer(MetaFactory& peer) { _hanlinPeer = &peer; }
    bool hanlinOwns(const Meta* meta) const { return _metaToDecl.count(meta) != 0; }""")
    header = replace_once(header, "    MetaToDeclMap _metaToDecl;",
        "    MetaToDeclMap _metaToDecl;\n    MetaFactory* _hanlinPeer = nullptr;")
    source = replace_once(source, "  if (declIt == this->_metaToDecl.end()) {", """  if (declIt == this->_metaToDecl.end()) {
    // Delegate only to the retained factory that actually created this model.
    // Never import a cache entry or synthesize a declaration in the other AST.
    if (_hanlinPeer && _hanlinPeer->hanlinOwns(meta)) {
      _hanlinPeer->validate(meta);
      return;
    }""")
    return header, source
