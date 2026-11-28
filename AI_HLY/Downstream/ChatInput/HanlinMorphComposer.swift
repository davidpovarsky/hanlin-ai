import SwiftUI
import HanlinChatUI

// Compatibility names for the original app and its unchanged tests.
// Canonical rendering and geometry live in the importable presentation package.
typealias HanlinMorphPageID<Page: Hashable> = HanlinChatUI.HanlinMorphPageID<Page>
typealias HanlinMorphGeometry = HanlinChatUI.HanlinMorphGeometry
typealias HanlinMorphComposer<Page: Hashable, Home: View, Detail: View, Input: View> = HanlinChatUI.HanlinMorphComposer<Page, Home, Detail, Input>
