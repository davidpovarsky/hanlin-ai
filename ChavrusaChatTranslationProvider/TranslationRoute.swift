// TranslationRoute.swift
// ChavrusaChatTranslationProvider

import Foundation
import HanlinScriptExtensions

enum TranslationRoute: Hashable {
    case apps
    case miniApp(HanlinScriptTranslationUISnapshot)
    case chat
}
