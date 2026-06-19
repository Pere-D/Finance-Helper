import SwiftUI

struct ScoreGaugeView: View {
    let score: Double

    var body: some View {
        ZStack {
            // Background arc (270° sweep, from 7:30 to 4:30 clockwise)
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color(.systemFill), style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Score arc — solid color matching the score level
            Circle()
                .trim(from: 0, to: CGFloat(score / 100) * 0.75)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.8), value: score)

            // Labels
            VStack(spacing: 2) {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(gaugeColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.8), value: score)
                Text("/ 100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Min / Max labels
            VStack {
                Spacer()
                HStack {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                    Spacer()
                    Text("100")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 18)
                }
            }
        }
        .frame(width: 200, height: 200)
    }

    private var gaugeColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .mint
        case 40..<60:  return .yellow
        case 20..<40:  return .orange
        default:       return .red
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        ScoreGaugeView(score: 78)
        ScoreGaugeView(score: 35)
    }
    .padding()
}
