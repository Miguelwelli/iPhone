import SwiftUI

/// Wraps children onto multiple lines, like the category chips in the assistant reference.
///
/// Implemented with SwiftUI's `Layout` protocol (iOS 16+), so it measures real sizes instead of
/// guessing and works with Dynamic Type.
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public struct Line {
        var indices: [Int] = []
        var size: CGSize = .zero
    }

    private func lines(for subviews: Subviews, width: CGFloat) -> [Line] {
        var result: [Line] = []
        var current = Line()
        let available = max(width, 1)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.size.width + spacing + size.width
            if needed > available && !current.indices.isEmpty {
                result.append(current)
                current = Line(indices: [index], size: size)
            } else {
                current.indices.append(index)
                current.size.width = current.indices.count == 1 ? size.width : current.size.width + spacing + size.width
                current.size.height = max(current.size.height, size.height)
            }
        }
        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let rows = lines(for: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.size.height } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = lines(for: subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.size.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.size.height + lineSpacing
        }
    }
}
