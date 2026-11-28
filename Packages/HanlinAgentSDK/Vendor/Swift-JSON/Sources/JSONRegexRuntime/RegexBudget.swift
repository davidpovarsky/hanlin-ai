// SPDX-License-Identifier: Apache-2.0
import JSON
package enum RegexFailure: Error, Sendable { case invalidPattern, unsupportedPattern }
package enum RegexBudget {
    package static func compileStep(meter: inout JSONWorkMeter) throws { try meter.work(subsystem: .regexCompileWorkUnits) }
    package static func searchStep(_ amount: UInt64 = 1, meter: inout JSONWorkMeter) throws {
        try meter.work(amount, subsystem: .regexSearchWorkUnits); try meter.charge(.aggregateRegexWorkUnits, amount)
    }
}
