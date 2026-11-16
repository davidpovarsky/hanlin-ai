// SPDX-License-Identifier: Apache-2.0
/// The supported Draft 2020-12 validation output formats.
public enum JSONValidationOutput: Sendable {
    /// Collect a validity flag without basic issue records.
    case flag
    /// Collect bounded flat issues and requested annotations.
    case basic
}
/// Whether diagnostic exhaustion throws or records explicit incompleteness.
public enum JSONValidationDiagnosticPolicy: Sendable {
    /// Throw when requested diagnostics cannot be fully retained.
    case complete
    /// Finish semantic evaluation and explicitly mark incomplete diagnostics.
    case bestEffort
}
