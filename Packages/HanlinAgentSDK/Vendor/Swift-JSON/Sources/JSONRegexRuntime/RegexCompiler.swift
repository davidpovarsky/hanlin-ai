// SPDX-License-Identifier: Apache-2.0
// Explicit emitter stack and backpatching selectively adapted from Regress src/emit.rs.
// Copyright (c) 2020 ridiculous_fish. See Licenses/regress-* and THIRD_PARTY_NOTICES.md.
import JSON

package enum RegexCompiler {
    private enum Task {
        case node(Int, backwards: Bool), instruction(RegexProgram.Instruction)
        case alternative([Int], Int, Bool, [Int]), alternativeMiddle([Int], Int, Bool, [Int], Int)
        case alternateFinish([Int])
        case loopFinish(Int), assertionFinish(Int)
    }
    package static func compile(_ pattern: String, meter: inout JSONWorkMeter) throws -> RegexProgram {
        try meter.checkpoint()
        var parser = RegexParser()
        let root = try parser.parse(pattern, meter: &meter)
        var instructions: [RegexProgram.Instruction] = [], tasks: [Task] = [], loops = 0
        func emit(_ instruction: RegexProgram.Instruction, meter: inout JSONWorkMeter) throws -> Int {
            try RegexBudget.compileStep(meter: &meter); try meter.charge(.regexProgramInstructions)
            try meter.retain(JSONLogicalWeights.regexInstruction)
            instructions.append(instruction); return instructions.count - 1
        }
        func push(_ task: Task, meter: inout JSONWorkMeter) throws {
            try RegexBudget.compileStep(meter: &meter); try meter.retain(16); tasks.append(task)
        }
        try push(.node(root, backwards: false), meter: &meter)
        while let task = tasks.popLast() {
            try meter.release(16); try RegexBudget.compileStep(meter: &meter)
            switch task {
            case .instruction(let instruction): _ = try emit(instruction, meter: &meter)
            case .node(let id, let backwards):
                let node = parser.nodes[id]
                switch node.kind {
                case .instruction(let instruction): _ = try emit(instruction, meter: &meter)
                case .sequence(let children):
                    // Lookbehind concatenation is emitted in reverse matching order.
                    if backwards { for child in children { try push(.node(child, backwards: true), meter: &meter) } }
                    else { for child in children.reversed() { try push(.node(child, backwards: false), meter: &meter) } }
                case .alternate(let alternatives): try push(.alternative(alternatives, 0, backwards, []), meter: &meter)
                case .capture(let group, let child):
                    _ = try emit(.beginCapture(group), meter: &meter)
                    try push(.instruction(.endCapture(group)), meter: &meter); try push(.node(child, backwards: backwards), meter: &meter)
                case .repetition(let child, let minimum, let maximum, let greedy):
                    let head = try emit(.enterLoop(id: loops, minimum: minimum, maximum: maximum, greedy: greedy, exit: 0, captures: node.captures), meter: &meter)
                    loops += 1; try push(.loopFinish(head), meter: &meter); try push(.node(child, backwards: backwards), meter: &meter)
                case .assertion(let child, let reverse, let negative):
                    let head = try emit(.assertion(backwards: reverse, negative: negative, continuation: 0, captures: node.captures), meter: &meter)
                    try push(.assertionFinish(head), meter: &meter); try push(.node(child, backwards: reverse), meter: &meter)
                case .namedReference: throw RegexFailure.invalidPattern // Resolved by the parser before emission.
                }
            case .alternative(let alternatives, let index, let backwards, let jumps):
                if index == alternatives.count - 1 {
                    try push(.alternateFinish(jumps), meter: &meter); try push(.node(alternatives[index], backwards: backwards), meter: &meter)
                } else {
                    let split = try emit(.split(0), meter: &meter)
                    try push(.alternativeMiddle(alternatives, index, backwards, jumps, split), meter: &meter)
                    try push(.node(alternatives[index], backwards: backwards), meter: &meter)
                }
            case .alternativeMiddle(let alternatives, let index, let backwards, var jumps, let split):
                let jump = try emit(.jump(0), meter: &meter)
                instructions[split] = .split(instructions.count)
                try meter.retain(8); try RegexBudget.compileStep(meter: &meter); jumps.append(jump)
                try push(.alternative(alternatives, index + 1, backwards, jumps), meter: &meter)
            case .alternateFinish(let jumps):
                for jump in jumps { try RegexBudget.compileStep(meter: &meter); instructions[jump] = .jump(instructions.count); try meter.release(8) }
            case .loopFinish(let head):
                _ = try emit(.loopAgain(head), meter: &meter)
                guard case .enterLoop(let id, let minimum, let maximum, let greedy, _, let captures) = instructions[head] else { throw RegexFailure.invalidPattern }
                instructions[head] = .enterLoop(id: id, minimum: minimum, maximum: maximum, greedy: greedy, exit: instructions.count, captures: captures)
            case .assertionFinish(let head):
                _ = try emit(.goal, meter: &meter)
                guard case .assertion(let backwards, let negative, _, let captures) = instructions[head] else { throw RegexFailure.invalidPattern }
                instructions[head] = .assertion(backwards: backwards, negative: negative, continuation: instructions.count, captures: captures)
            }
        }
        _ = try emit(.goal, meter: &meter)
        var classBytes: UInt64 = 0
        for item in parser.classes { try RegexBudget.compileStep(meter: &meter); classBytes += 16 + UInt64(item.parts.count) * 16 }
        try meter.release(parser.temporaryBytes - classBytes)
        return .init(instructions: instructions, classes: parser.classes, captureCount: parser.captureCount, loopCount: loops)
    }
}
