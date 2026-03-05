import SwiftUI

struct BandwidthChartView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var speedHistory: [Double] = Array(repeating: 0, count: 30)

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bandwidth")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                Text(downloadManager.totalSpeed.formattedSpeed)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.primary)
            }

            // Chart
            GeometryReader { geo in
                let maxSpeed = max(speedHistory.max() ?? 1, 1)
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // Grid lines
                    ForEach(0..<4) { i in
                        let y = h * CGFloat(i) / 3
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Theme.border.opacity(0.3), lineWidth: 0.5)
                    }

                    // Speed area fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        for (index, speed) in speedHistory.enumerated() {
                            let x = w * CGFloat(index) / CGFloat(speedHistory.count - 1)
                            let y = h - (h * CGFloat(speed / maxSpeed))
                            if index == 0 {
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Theme.primary.opacity(0.3), Theme.primary.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Speed line
                    Path { path in
                        for (index, speed) in speedHistory.enumerated() {
                            let x = w * CGFloat(index) / CGFloat(speedHistory.count - 1)
                            let y = h - (h * CGFloat(speed / maxSpeed))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Theme.primary, lineWidth: 1.5)
                }
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .onReceive(timer) { _ in
            speedHistory.append(downloadManager.totalSpeed)
            if speedHistory.count > 30 {
                speedHistory.removeFirst()
            }
        }
    }
}
