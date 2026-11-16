// SPDX-License-Identifier: Apache-2.0
// Instruction and explicit emitter concepts selectively adapted from Regress.
// Copyright (c) 2020 ridiculous_fish. See Licenses/regress-* and THIRD_PARTY_NOTICES.md.
import JSON

/// Immutable package-private Unicode scalar bytecode; each search owns its mutable state.
package struct RegexProgram: Sendable {
    package enum Instruction: Sendable {
        case character(UInt32), anyExceptLineTerminator, start, end, goal
        case bracket(Int), wordBoundary(invert: Bool), backreference(Int)
        case beginCapture(Int), endCapture(Int)
        case jump(Int), split(Int)
        case enterLoop(id: Int, minimum: UInt64, maximum: UInt64, greedy: Bool, exit: Int, captures: Range<Int>)
        case loopAgain(Int)
        case assertion(backwards: Bool, negative: Bool, continuation: Int, captures: Range<Int>)
    }
    package struct CharacterClass: Sendable {
        package enum Part: Sendable {
            case range(UInt32, UInt32)
            case digit(invert: Bool), word(invert: Bool), space(invert: Bool)
            case property(Int, invert: Bool)
        }
        package let inverted: Bool
        package let parts: [Part]
    }
    package let instructions: [Instruction]
    package let classes: [CharacterClass]
    package let captureCount: Int
    package let loopCount: Int
    package func search(_ subject: String, meter: inout JSONWorkMeter) throws -> Bool {
        try RegexVM.search(self, subject: subject, meter: &meter)
    }
}
