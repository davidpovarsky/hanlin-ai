#pragma once

#include <clang/AST/ASTContext.h>
#include <clang/Basic/SourceManager.h>
#include <clang/Lex/Lexer.h>
#include <set>

namespace HanlinDual {

// NS_OPTIONS/CF_OPTIONS deliberately use an integer typedef plus an anonymous
// enum in C++. Other SDK macros use that shape in both languages and must keep
// the original primitive signature. Inspect actual retained expansion ancestry;
// neither declaration shape nor a vendor macro's spelling establishes options.
inline bool isOriginalOptionsExpansion(clang::SourceLocation location,
                                       const clang::ASTContext& context) {
    const auto& sources = context.getSourceManager();
    std::set<unsigned> visited;
    for (unsigned depth = 0; depth < 64 && location.isMacroID(); ++depth) {
        if (!visited.insert(location.getRawEncoding()).second) return false;
        const auto name = clang::Lexer::getImmediateMacroName(location, sources, context.getLangOpts());
        if (name == "NS_OPTIONS" || name == "CF_OPTIONS") return true;
        location = sources.getImmediateMacroCallerLoc(location);
    }
    return false;
}

} // namespace HanlinDual
