#if canImport(TranslationUIProvider)
import HanlinLocalization
// TranslationRoute.swift
// ChavrusaChatTranslationProvider

import Foundation
import HanlinScriptExtensions

public enum TranslationRoute: Hashable {
    case apps
    case miniApp(HanlinScriptTranslationUISnapshot)
    case chat
}

#endif
