import SwiftUI

struct BudgetSankeyCanvas: View {
    let incomeItems: [(name: String, amount: Double, color: Color)]
    let expenseItems: [(name: String, amount: Double, color: Color)]
    let currency: String

    private var totalIncome: Double { incomeItems.reduce(0) { $0 + $1.amount } }
    private var totalExpenses: Double { expenseItems.reduce(0) { $0 + $1.amount } }

    private var rightItems: [(name: String, amount: Double, color: Color)] {
        var items = Array(expenseItems.prefix(9))
        let surplus = totalIncome - totalExpenses
        if surplus > 0.5 { items.append((NSLocalizedString("surplus", comment: ""), surplus, .green)) }
        return items
    }

    var body: some View {
        Canvas { ctx, size in
            guard totalIncome > 0 else { return }

            let nodeW: CGFloat = 12
            let topPad: CGFloat = 10
            let botPad: CGFloat = 10
            let nodeGap: CGFloat = 3

            let leftNodeX: CGFloat = 76
            let rightNodeX: CGFloat = size.width - 108
            let drawH = size.height - topPad - botPad

            let totalRight = rightItems.reduce(0) { $0 + $1.amount }
            let scaleBase = max(totalIncome, totalRight, 1)
            let scale = drawH / CGFloat(scaleBase)

            // Income bar centered vertically
            let incomeBarH = CGFloat(totalIncome) * scale
            let incomeBarY = topPad + (drawH - incomeBarH) / 2

            // Right items stacked from center
            let rightContentH = CGFloat(totalRight) * scale
            let rightGapsH = CGFloat(max(rightItems.count - 1, 0)) * nodeGap
            let rightStartY = topPad + max(0, (drawH - rightContentH - rightGapsH) / 2)

            var rightRects: [CGRect] = []
            var curY = rightStartY
            for item in rightItems {
                let h = max(CGFloat(item.amount) * scale, 4)
                rightRects.append(CGRect(x: rightNodeX, y: curY, width: nodeW, height: h))
                curY += h + nodeGap
            }

            // Ribbon heights proportional to income bar (always sum to incomeBarH)
            let incomeRibbonScale = incomeBarH / CGFloat(max(totalRight, 1))

            // Draw ribbons behind nodes
            var incomeOffset: CGFloat = 0
            for (i, item) in rightItems.enumerated() {
                let rH = CGFloat(item.amount) * incomeRibbonScale
                let lY1 = incomeBarY + incomeOffset
                let lY2 = lY1 + rH
                let rY1 = rightRects[i].minY
                let rY2 = rightRects[i].maxY
                let mx = (leftNodeX + nodeW + rightNodeX) / 2

                var path = Path()
                path.move(to: CGPoint(x: leftNodeX + nodeW, y: lY1))
                path.addCurve(to: CGPoint(x: rightNodeX, y: rY1),
                              control1: CGPoint(x: mx, y: lY1),
                              control2: CGPoint(x: mx, y: rY1))
                path.addLine(to: CGPoint(x: rightNodeX, y: rY2))
                path.addCurve(to: CGPoint(x: leftNodeX + nodeW, y: lY2),
                              control1: CGPoint(x: mx, y: rY2),
                              control2: CGPoint(x: mx, y: lY2))
                path.closeSubpath()
                ctx.fill(path, with: .color(item.color.opacity(0.18)))

                incomeOffset += rH
            }

            // Draw income bar (colored segments per income source)
            var segY = incomeBarY
            for item in incomeItems {
                let segH = CGFloat(item.amount / max(totalIncome, 1)) * incomeBarH
                ctx.fill(
                    Path(roundedRect: CGRect(x: leftNodeX, y: segY, width: nodeW, height: max(segH, 2)),
                         cornerRadius: 2),
                    with: .color(item.color.opacity(0.8))
                )
                segY += segH
            }

            // Draw expense bars
            for (i, item) in rightItems.enumerated() {
                ctx.fill(
                    Path(roundedRect: rightRects[i], cornerRadius: 3),
                    with: .color(item.color.opacity(0.75))
                )
            }

            // Income label (left of bar, centered vertically)
            ctx.draw(
                Text(NSLocalizedString("income_section", comment: ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary),
                at: CGPoint(x: leftNodeX - 5, y: incomeBarY + incomeBarH / 2),
                anchor: .trailing
            )

            // Expense labels (right of bars)
            for (i, item) in rightItems.enumerated() {
                let rect = rightRects[i]
                guard rect.height >= 6 else { continue }
                let label = item.name.count > 14 ? String(item.name.prefix(13)) + "…" : item.name
                ctx.draw(
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary),
                    at: CGPoint(x: rightNodeX + nodeW + 5, y: rect.midY),
                    anchor: .leading
                )
            }
        }
    }
}
