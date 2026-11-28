import SwiftUI

/// Honest absence of a canonical runtime report, not a compatibility assessment.
struct SkillCompatibilityUnknownSection: View {
    let identifierScope: String

    var body: some View {
        Section(header: Text(SkillL10n.string("Compatibility"))) {
            LabeledContent(SkillL10n.string("Status"), value: SkillL10n.string("Unknown"))
                .accessibilityValue(SkillL10n.string("Unknown"))
                .accessibilityIdentifier("hanlin-skill-\(identifierScope)-compatibility-status")
            LabeledContent(SkillL10n.string("Last tested"), value: SkillL10n.string("Not recorded"))
                .accessibilityValue(SkillL10n.string("Not recorded"))
                .accessibilityIdentifier("hanlin-skill-\(identifierScope)-compatibility-last-tested")
            Text(SkillL10n.string("Installing or enabling a skill does not verify that its actions can run."))
                .font(HanlinTypography.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
