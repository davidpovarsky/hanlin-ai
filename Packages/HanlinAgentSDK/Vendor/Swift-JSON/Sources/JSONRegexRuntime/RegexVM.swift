// SPDX-License-Identifier: Apache-2.0
// Bytecode loop, capture-reset and assertion concepts selectively adapted from Regress.
// Copyright (c) 2020 ridiculous_fish. See Licenses/regress-* and THIRD_PARTY_NOTICES.md.
import JSON

/// One scalar backtracking engine. Dispatch, candidates, comparisons and all owned state are metered.
package enum RegexVM {
    private struct Capture { var start: Int?; var end: Int? }
    private struct Loop { var active = false; var count: UInt64 = 0; var position = 0; var blocked = false }
    private struct State {
        var pc: Int
        var position: Int
        var backwards: Bool
        var captures: [Capture]
        var loops: [Loop]
    }
    private struct Return { let negative: Bool; let captures: Range<Int> }
    private struct Context { var state: State; var alternatives: [State] = []; let returning: Return? }

    private static func word(_ scalar: UInt32) -> Bool {
        (65...90).contains(scalar) || (97...122).contains(scalar) || (48...57).contains(scalar) || scalar == 95
    }
    private static func space(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 9...13, 32, 160, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff: true
        default: false
        }
    }
    private static func matches(_ item: RegexProgram.CharacterClass, _ scalar: UInt32, meter: inout JSONWorkMeter) throws -> Bool {
        var result = false
        for part in item.parts {
            try RegexBudget.searchStep(meter: &meter)
            switch part {
            case .range(let lo, let hi): result = lo <= scalar && scalar <= hi
            case .digit(let inverted): result = (48...57).contains(scalar) != inverted
            case .word(let inverted): result = word(scalar) != inverted
            case .space(let inverted): result = space(scalar) != inverted
            case .property(let id, let inverted): result = try RegexUnicodeTables.contains(id, scalar, meter: &meter) != inverted
            }
            if result { break }
        }
        return result != item.inverted
    }
    package static func search(_ program: RegexProgram, subject: String, meter: inout JSONWorkMeter) throws -> Bool {
        try meter.checkpoint(); try meter.beginRegexSearch()
        var input: [UInt32] = [], bytes: UInt64 = 0
        func retain(_ amount: UInt64, meter: inout JSONWorkMeter) throws {
            try meter.charge(.regexRetainedBytes, amount); try meter.retain(amount)
        }
        func release(_ amount: UInt64, meter: inout JSONWorkMeter) throws {
            try meter.releaseRegexState(amount); try meter.release(amount)
        }
        for _ in subject.utf8 { try RegexBudget.searchStep(meter: &meter); bytes += 1; try meter.require(.stringBytes, bytes) }
        for scalar in subject.unicodeScalars { try RegexBudget.searchStep(meter: &meter); try retain(4, meter: &meter); input.append(scalar.value) }
        let stateBytes = JSONLogicalWeights.regexStateRecord + UInt64(program.captureCount) * 16 + UInt64(program.loopCount) * 32
        func clone(_ state: State, meter: inout JSONWorkMeter) throws -> State {
            try retain(stateBytes, meter: &meter)
            var captures: [Capture] = [], loops: [Loop] = []
            for capture in state.captures { try RegexBudget.searchStep(meter: &meter); captures.append(capture) }
            for loop in state.loops { try RegexBudget.searchStep(meter: &meter); loops.append(loop) }
            try RegexBudget.searchStep(meter: &meter)
            return .init(pc: state.pc, position: state.position, backwards: state.backwards, captures: captures, loops: loops)
        }
        func clear(_ range: Range<Int>, in state: inout State, meter: inout JSONWorkMeter) throws {
            for group in range { try RegexBudget.searchStep(meter: &meter); state.captures[group] = .init(start: nil, end: nil) }
        }
        func destroy(_ context: Context, meter: inout JSONWorkMeter) throws {
            for _ in context.alternatives { try RegexBudget.searchStep(meter: &meter); try release(stateBytes, meter: &meter) }
            try release(stateBytes + 16, meter: &meter)
        }
        /// A failed assertion resumes its parent. Negative assertions succeed only on exhausted search.
        /// Each assertion has an explicit context; Swift call-stack depth never follows pattern nesting.
        func retry(_ contexts: inout [Context], meter: inout JSONWorkMeter) throws -> Bool {
            while !contexts.isEmpty {
                try RegexBudget.searchStep(meter: &meter)
                let last = contexts.count - 1
                if let alternate = contexts[last].alternatives.popLast() {
                    try release(stateBytes, meter: &meter); contexts[last].state = alternate; return true
                }
                let failed = contexts.removeLast(); let returning = failed.returning
                try destroy(failed, meter: &meter)
                if let returning, returning.negative {
                    guard !contexts.isEmpty else { return false }
                    try clear(returning.captures, in: &contexts[contexts.count-1].state, meter: &meter)
                    return true
                }
            }
            return false
        }
        var matched = false
        candidate: for start in 0...input.count {
            try RegexBudget.searchStep(meter: &meter); try retain(stateBytes + 16, meter: &meter)
            var captures: [Capture] = [], loops: [Loop] = []
            for _ in 0..<program.captureCount { try RegexBudget.searchStep(meter: &meter); captures.append(.init(start: nil, end: nil)) }
            for _ in 0..<program.loopCount { try RegexBudget.searchStep(meter: &meter); loops.append(.init()) }
            var contexts = [Context(state: .init(pc: 0, position: start, backwards: false, captures: captures, loops: loops), returning: nil)]
            captures = []; loops = []
            while !contexts.isEmpty {
                try RegexBudget.searchStep(meter: &meter)
                let c = contexts.count - 1, pc = contexts[c].state.pc, position = contexts[c].state.position
                let backwards = contexts[c].state.backwards
                let subjectIndex: Int? = backwards ? (position > 0 ? position - 1 : nil) : (position < input.count ? position : nil)
                var success = true
                switch program.instructions[pc] {
                case .goal:
                    let finished = contexts.removeLast()
                    if let returning = finished.returning {
                        let parent = contexts.count - 1
                        if !returning.negative {
                            try RegexBudget.searchStep(UInt64(program.captureCount), meter: &meter)
                            contexts[parent].state.captures = finished.state.captures
                        }
                        try destroy(finished, meter: &meter)
                        if returning.negative { success = try retry(&contexts, meter: &meter) }
                        if !success { break }
                        continue
                    }
                    try destroy(finished, meter: &meter); matched = true; break
                case .character(let scalar):
                    success = subjectIndex.map { input[$0] == scalar } ?? false
                    if success { contexts[c].state.position += backwards ? -1 : 1; contexts[c].state.pc += 1 }
                case .anyExceptLineTerminator:
                    if let i = subjectIndex { let scalar = input[i]; success = scalar != 10 && scalar != 13 && scalar != 0x2028 && scalar != 0x2029 } else { success = false }
                    if success { contexts[c].state.position += backwards ? -1 : 1; contexts[c].state.pc += 1 }
                case .bracket(let id):
                    success = try subjectIndex.map { try matches(program.classes[id], input[$0], meter: &meter) } ?? false
                    if success { contexts[c].state.position += backwards ? -1 : 1; contexts[c].state.pc += 1 }
                case .start: success = position == 0; if success { contexts[c].state.pc += 1 }
                case .end: success = position == input.count; if success { contexts[c].state.pc += 1 }
                case .wordBoundary(let invert):
                    let before = position > 0 && word(input[position - 1]), after = position < input.count && word(input[position])
                    success = (before != after) != invert; if success { contexts[c].state.pc += 1 }
                case .jump(let target): contexts[c].state.pc = target
                case .split(let secondary):
                    var alternate = try clone(contexts[c].state, meter: &meter); alternate.pc = secondary
                    contexts[c].alternatives.append(alternate); contexts[c].state.pc += 1
                case .beginCapture(let group):
                    contexts[c].state.captures[group] = .init(start: position, end: nil); contexts[c].state.pc += 1
                case .endCapture(let group): contexts[c].state.captures[group].end = position; contexts[c].state.pc += 1
                case .backreference(let group):
                    let capture = contexts[c].state.captures[group]
                    if let a = capture.start, let b = capture.end {
                        let lo = min(a,b), hi = max(a,b), length = hi - lo
                        if backwards {
                            success = length <= position
                            if success {
                                for offset in 0..<length { try RegexBudget.searchStep(meter: &meter); if input[hi-1-offset] != input[position-1-offset] { success = false; break } }
                                if success { contexts[c].state.position -= length }
                            }
                        } else {
                            success = length <= input.count - position
                            if success {
                                for offset in 0..<length { try RegexBudget.searchStep(meter: &meter); if input[lo+offset] != input[position+offset] { success = false; break } }
                                if success { contexts[c].state.position += length }
                            }
                        }
                    } // Unmatched or not-yet-participating captures match the empty string in ECMAScript.
                    if success { contexts[c].state.pc += 1 }
                case .enterLoop(let id, let minimum, let maximum, let greedy, let exit, let captures):
                    if !contexts[c].state.loops[id].active { contexts[c].state.loops[id] = .init(active: true, count: 0, position: position, blocked: false) }
                    let loop = contexts[c].state.loops[id]
                    let canExit = loop.count >= minimum
                    let canBody = loop.count < maximum && !loop.blocked
                    if !canBody {
                        success = canExit
                        if success { contexts[c].state.loops[id].active = false; contexts[c].state.pc = exit }
                    } else if !canExit {
                        try clear(captures, in: &contexts[c].state, meter: &meter)
                        contexts[c].state.loops[id].position = position; contexts[c].state.pc += 1
                    } else {
                        var alternate = try clone(contexts[c].state, meter: &meter)
                        if greedy {
                            alternate.loops[id].active = false; alternate.pc = exit
                            contexts[c].alternatives.append(alternate)
                            try clear(captures, in: &contexts[c].state, meter: &meter)
                            contexts[c].state.loops[id].position = position; contexts[c].state.pc += 1
                        } else {
                            try clear(captures, in: &alternate, meter: &meter)
                            alternate.loops[id].position = position; alternate.pc += 1
                            contexts[c].alternatives.append(alternate)
                            contexts[c].state.loops[id].active = false; contexts[c].state.pc = exit
                        }
                    }
                case .loopAgain(let head):
                    guard case .enterLoop(let id, let minimum, _, _, _, _) = program.instructions[head] else { throw RegexFailure.invalidPattern }
                    let loop = contexts[c].state.loops[id]
                    if position == loop.position && loop.count >= minimum { success = false }
                    else {
                        contexts[c].state.loops[id].count += 1 // Finite dispatch budget prevents UInt64 overflow.
                        contexts[c].state.loops[id].blocked = position == loop.position && contexts[c].state.loops[id].count >= minimum
                        contexts[c].state.pc = head
                    }
                case .assertion(let reverse, let negative, let continuation, let captures):
                    var state = try clone(contexts[c].state, meter: &meter)
                    try clear(captures, in: &state, meter: &meter)
                    state.pc = pc + 1; state.backwards = reverse
                    contexts[c].state.pc = continuation
                    try retain(16, meter: &meter)
                    contexts.append(.init(state: state, returning: .init(negative: negative, captures: captures)))
                }
                if matched { break }
                if !success { if try !retry(&contexts, meter: &meter) { break } }
            }
            if matched { break candidate }
        }
        try release(UInt64(input.count) * 4, meter: &meter)
        return matched
    }
}
