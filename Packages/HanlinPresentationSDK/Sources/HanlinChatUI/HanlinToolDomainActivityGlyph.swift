#if canImport(SwiftUI)
import SwiftUI

/// Decorative motion for an observed tool invocation, never a progress meter.
/// The caller owns the real lifetime, visibility and Reduce Motion clock.
struct HanlinToolDomainActivityGlyph: View {
    let family: HanlinToolActivityHeader.Family
    let seconds: Double
    let color: Color

    var body: some View {
        Canvas { context, size in
            switch family {
            case .memorySave, .memoryRecall, .memoryUpdate:
                drawMemory(context, size: size)
            default:
                drawCalendar(context, size: size)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var phase: Double {
        seconds.truncatingRemainder(dividingBy: 2.4) / 2.4
    }

    private func drawCalendar(_ context: GraphicsContext, size: CGSize) {
        let origin = CGPoint(x: 7, y: (size.height - 27) / 2)
        let page = CGRect(origin: origin, size: CGSize(width: 33, height: 27))
        context.stroke(Path(roundedRect: page, cornerRadius: 5),
                       with: .color(color.opacity(0.70)), lineWidth: 1.3)
        var rule = Path()
        rule.move(to: CGPoint(x: page.minX + 1, y: page.minY + 8))
        rule.addLine(to: CGPoint(x: page.maxX - 1, y: page.minY + 8))
        context.stroke(rule, with: .color(color.opacity(0.45)), lineWidth: 1)
        for index in 0..<6 {
            let x = page.minX + 7 + CGFloat(index % 3) * 9
            let y = page.minY + 13 + CGFloat(index / 3) * 8
            let emphasis = family == .calendarSearch
                ? 0.25 + 0.65 * max(0, sin(phase * .pi * 2 - Double(index) * 0.6))
                : 0.30
            context.fill(Path(roundedRect: CGRect(x: x - 2, y: y - 2, width: 4, height: 4), cornerRadius: 1),
                         with: .color(color.opacity(emphasis)))
        }
        let center = CGPoint(x: 58, y: size.height / 2)
        let pulse = 0.55 + 0.30 * sin(phase * .pi * 2)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26)),
                     with: .color(color.opacity(0.06 + 0.04 * pulse)))
        var mark = Path()
        switch family {
        case .calendarCreate:
            let length = CGFloat(5 + pulse * 2)
            mark.move(to: CGPoint(x: center.x - length, y: center.y))
            mark.addLine(to: CGPoint(x: center.x + length, y: center.y))
            mark.move(to: CGPoint(x: center.x, y: center.y - length))
            mark.addLine(to: CGPoint(x: center.x, y: center.y + length))
        case .calendarDelete:
            let shift = CGFloat(sin(phase * .pi * 2) * 2)
            mark.move(to: CGPoint(x: center.x - 7 + shift, y: center.y))
            mark.addLine(to: CGPoint(x: center.x + 7 + shift, y: center.y))
        case .calendarComplete:
            mark.move(to: CGPoint(x: center.x - 7, y: center.y))
            mark.addLine(to: CGPoint(x: center.x - 2, y: center.y + 5))
            mark.addLine(to: CGPoint(x: center.x + 8, y: center.y - 6))
        case .calendarUpdate:
            let shift = CGFloat(sin(phase * .pi * 2) * 2)
            mark.move(to: CGPoint(x: center.x - 6 + shift, y: center.y + 6))
            mark.addLine(to: CGPoint(x: center.x + 5 + shift, y: center.y - 5))
            mark.move(to: CGPoint(x: center.x - 7, y: center.y + 8))
            mark.addLine(to: CGPoint(x: center.x + 7, y: center.y + 8))
        case .calendarSearch:
            let shift = CGFloat(sin(phase * .pi * 2) * 2)
            mark.addEllipse(in: CGRect(x: center.x - 7 + shift, y: center.y - 7, width: 11, height: 11))
            mark.move(to: CGPoint(x: center.x + 3 + shift, y: center.y + 3))
            mark.addLine(to: CGPoint(x: center.x + 8 + shift, y: center.y + 8))
        case .calendarAccess:
            mark.addRoundedRect(in: CGRect(x: center.x - 6, y: center.y - 1, width: 12, height: 10),
                                cornerSize: CGSize(width: 2, height: 2))
            mark.move(to: CGPoint(x: center.x - 4, y: center.y - 1))
            mark.addCurve(to: CGPoint(x: center.x + 4, y: center.y - 1),
                          control1: CGPoint(x: center.x - 4, y: center.y - 11),
                          control2: CGPoint(x: center.x + 4, y: center.y - 11))
        default:
            for index in 0..<3 {
                let y = center.y - 5 + CGFloat(index) * 5
                mark.move(to: CGPoint(x: center.x - 7, y: y))
                mark.addLine(to: CGPoint(x: center.x + 4 + CGFloat(index % 2) * 3, y: y))
            }
        }
        context.stroke(mark, with: .color(color.opacity(0.65 + pulse * 0.25)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func drawMemory(_ context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: 22, y: size.height / 2)
        for index in 0..<3 {
            let rect = CGRect(x: center.x - 11, y: center.y - 10 + CGFloat(index) * 7,
                              width: 22, height: 7)
            context.stroke(Path(roundedRect: rect, cornerRadius: 3),
                           with: .color(color.opacity(0.38 + 0.15 * Double(index))), lineWidth: 1.2)
        }
        var route = Path()
        route.move(to: CGPoint(x: 39, y: center.y))
        route.addLine(to: CGPoint(x: 68, y: center.y))
        context.stroke(route, with: .color(color.opacity(0.18)), lineWidth: 1)
        for index in 0..<3 {
            let cycle = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
            let position: Double
            switch family {
            case .memoryRecall: position = cycle
            case .memoryUpdate: position = (1 + sin(cycle * .pi * 2)) / 2
            default: position = 1 - cycle
            }
            let x = CGFloat(40 + position * 27)
            let alpha = 0.15 + 0.7 * sin(cycle * .pi)
            context.fill(Path(ellipseIn: CGRect(x: x - 2, y: center.y - 2, width: 4, height: 4)),
                         with: .color(color.opacity(alpha)))
        }
    }
}
#endif
