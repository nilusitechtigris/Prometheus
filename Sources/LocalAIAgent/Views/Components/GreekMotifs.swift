import SwiftUI

// Line drawings from Greek pottery and temples. They're plain paths that never change, so they cost one
// draw, and none of them sits behind text.

/// A running Greek key that fills its rect from the left. Stroke it. It's four units tall, and one
/// turn is six units wide, so whole-number units land on the pixel grid.
struct Meander: Shape {
    var unit: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY
        let bottom = top + unit * 4
        let middle = top + unit * 2
        var x = rect.minX
        path.move(to: CGPoint(x: x, y: bottom))
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x + unit * 4, y: top))
            path.addLine(to: CGPoint(x: x + unit * 4, y: middle))
            path.addLine(to: CGPoint(x: x + unit * 2, y: middle))
            path.addLine(to: CGPoint(x: x + unit * 2, y: bottom))
            path.addLine(to: CGPoint(x: x + unit * 6, y: bottom))
            x += unit * 6
        }
        return path
    }
}

/// A band of Greek key, like the friezes on black-figure pottery. Full width, it stands in for a rule.
struct MeanderFrieze: View {
    var color: Color = Forge.faint

    var body: some View {
        Meander()
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter))
            .frame(height: 9)
            .padding(0.5)
            .clipped()
            .accessibilityHidden(true)
    }
}

/// A Doric column in outline: abacus, echinus and fluted shaft on a step. Stroke it.
struct DoricColumn: Shape {
    var flutes = 2

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let abacus = (w * 0.16).rounded()
        let echinus = (w * 0.14).rounded()
        let step = (w * 0.16).rounded()
        let shaftTop = rect.minY + abacus + echinus
        let shaftBottom = rect.maxY - step
        let topInset = w * 0.16
        let bottomInset = w * 0.09

        var path = Path()
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: w, height: abacus))
        path.move(to: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + abacus))
        path.addLine(to: CGPoint(x: rect.minX + topInset, y: shaftTop))
        path.addLine(to: CGPoint(x: rect.maxX - topInset, y: shaftTop))
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + abacus))
        path.addRect(CGRect(x: rect.minX, y: shaftBottom, width: w, height: step))

        // The shaft's two sides and its flutes, all narrowing a little towards the top.
        for line in 0...(flutes + 1) {
            let share = CGFloat(line) / CGFloat(flutes + 1)
            let top = rect.minX + topInset + (w - topInset * 2) * share
            let bottom = rect.minX + bottomInset + (w - bottomInset * 2) * share
            path.move(to: CGPoint(x: top, y: shaftTop))
            path.addLine(to: CGPoint(x: bottom, y: shaftBottom))
        }
        return path
    }
}

/// A laurel wreath: two branches rising from the foot and almost meeting at the top. Fill it.
struct LaurelWreath: Shape {
    var leavesPerBranch = 11

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = side * 0.43
        let leaf = side * 0.12
        let start = 14.0, end = 158.0

        func spot(_ degrees: Double, branch: Double) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: center.x + radius * sin(angle) * branch, y: center.y + radius * cos(angle))
        }

        var path = Path()
        for branch in [-1.0, 1.0] {
            var stem = Path()
            stem.move(to: spot(4, branch: branch))
            for degrees in stride(from: 8.0, through: end, by: 4) {
                stem.addLine(to: spot(degrees, branch: branch))
            }
            path.addPath(stem.strokedPath(StrokeStyle(lineWidth: max(side * 0.008, 0.75), lineCap: .round)))

            for index in 0..<leavesPerBranch {
                let share = Double(index) / Double(leavesPerBranch - 1)
                let degrees = start + (end - start) * share
                let base = spot(degrees, branch: branch)
                let next = spot(degrees + 2, branch: branch)
                let heading = atan2(next.y - base.y, next.x - base.x)
                let length = leaf * (1 - 0.32 * share)
                // Each joint carries a leaf either side of the stem, opening away from it.
                path.addPath(Self.leaf(at: base, heading: heading + 0.62 * branch, length: length))
                path.addPath(Self.leaf(at: base, heading: heading - 0.42 * branch, length: length * 0.86))
            }
        }
        return path
    }

    private static func leaf(at base: CGPoint, heading: Double, length: CGFloat) -> Path {
        let tip = CGPoint(x: base.x + length * cos(heading), y: base.y + length * sin(heading))
        let middle = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
        let bulge = length * 0.42
        let normal = CGPoint(x: -sin(heading) * bulge, y: cos(heading) * bulge)
        var path = Path()
        path.move(to: base)
        path.addQuadCurve(to: tip, control: CGPoint(x: middle.x + normal.x, y: middle.y + normal.y))
        path.addQuadCurve(to: base, control: CGPoint(x: middle.x - normal.x, y: middle.y - normal.y))
        path.closeSubpath()
        return path
    }
}
