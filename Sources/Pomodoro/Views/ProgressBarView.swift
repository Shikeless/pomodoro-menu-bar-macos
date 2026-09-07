import SwiftUI

/// Segment widths mirror each phase's share of one round, so the fill edge
/// crosses a colour boundary at exactly the moment that phase ends.
///
/// Two identical copies of the same three segments: the track underneath at low
/// opacity, and the fill masked to the elapsed fraction on top. The boundary
/// between them reads as the progress edge.
struct ProgressBarView: View {
    let config: Config
    let progress: Double

    private let height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let edge = width * min(1, max(0, progress))

            ZStack(alignment: .leading) {
                segments(width: width).opacity(0.16)
                segments(width: width)
                    .opacity(0.9)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: edge)
                    }
                Rectangle()
                    .fill(.primary.opacity(0.55))
                    .frame(width: 1.5)
                    .offset(x: max(0, edge - 1.5))
                    .opacity(progress > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
    }

    private func segments(width: CGFloat) -> some View {
        let cycle = CGFloat(Phase.allCases.reduce(0) { $0 + config[$1] })
        return HStack(spacing: 0) {
            ForEach(Phase.allCases) { phase in
                phase.color.frame(width: width * CGFloat(config[phase]) / max(1, cycle))
            }
        }
    }
}
