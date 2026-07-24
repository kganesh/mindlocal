import SwiftUI
import SwiftData

/// The people/relationship graph: each person a node, each `PersonRelationship`
/// an edge, laid out with a small force-directed simulation and anchored on "Me".
/// Nodes are draggable; tap to open a person. (POLE+O / entity-graph surface.)
struct PeopleGraphView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var relationships: [PersonRelationship]
    @Query private var conflicts: [Conflict]

    @State private var positions: [UUID: CGPoint] = [:]
    @State private var laidOut = false

    /// Each person's relationship temperature, computed from their conflicts.
    private var personTemps: [UUID: RelationshipTemperature] {
        Dictionary(uniqueKeysWithValues: people.map {
            ($0.id, RelationshipTemperature.of($0, conflicts: conflicts))
        })
    }

    /// Each edge's temperature (the hotter of its endpoints).
    private var edgeTemps: [UUID: RelationshipTemperature] {
        Dictionary(uniqueKeysWithValues: relationships.map {
            ($0.id, RelationshipTemperature.ofEdge($0, conflicts: conflicts))
        })
    }

    /// Temperatures present in the graph, hottest first — the legend's contents.
    private var presentTemps: [RelationshipTemperature] {
        Set(people.filter { !$0.isMe }.map { personTemps[$0.id] ?? .warm })
            .sorted { $0.severity > $1.severity }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                edgeLayer
                nodeLayer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if !laidOut, geo.size.width > 0 {
                    computeLayout(in: geo.size)
                    laidOut = true
                }
            }
        }
        .overlay(alignment: .top) {
            if !presentTemps.isEmpty {
                TemperatureLegend(present: presentTemps).padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if relationships.isEmpty && !people.isEmpty {
                Text("Add relationships from a person's page to connect the graph.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 10)
            }
        }
    }

    private var edgeLayer: some View {
        let temps = edgeTemps
        return Canvas { ctx, _ in
            for edge in relationships {
                guard let a = edge.subject?.id, let b = edge.object?.id,
                      let p1 = positions[a], let p2 = positions[b] else { continue }
                let temp = temps[edge.id] ?? .warm
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                ctx.stroke(path, with: .color(temp.color.opacity(temp == .dormant ? 0.35 : 0.9)), lineWidth: 2)

                // A background plate behind the label so it reads against any
                // edge color or crossing line, instead of plain text sitting
                // directly on top of the stroke.
                let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                let label = Text(edge.type.label).font(.caption2.weight(.medium)).foregroundStyle(.primary)
                let resolved = ctx.resolve(label)
                let size = resolved.measure(in: CGSize(width: 160, height: 20))
                let padH: CGFloat = 5, padV: CGFloat = 2
                let plate = CGRect(
                    x: mid.x - size.width / 2 - padH, y: mid.y - size.height / 2 - padV,
                    width: size.width + padH * 2, height: size.height + padV * 2
                )
                ctx.fill(Path(roundedRect: plate, cornerRadius: 5), with: .color(Color(.systemBackground).opacity(0.85)))
                ctx.draw(label, at: mid)
            }
        }
    }

    private var nodeLayer: some View {
        ForEach(people) { person in
            NavigationLink {
                PersonDetailView(person: person)
            } label: {
                nodeLabel(person)
            }
            .buttonStyle(.plain)
            .position(positions[person.id] ?? CGPoint(x: 120, y: 120))
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { positions[person.id] = $0.location }
            )
        }
    }

    private func nodeLabel(_ person: Person) -> some View {
        let ringColor = person.isMe ? Color.accentColor : (personTemps[person.id] ?? .warm).color
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(person.isMe ? Color.accentColor : Color(.secondarySystemBackground))
                    .overlay(Circle().stroke(ringColor, lineWidth: person.isMe ? 1.5 : 2.5))
                    .frame(width: 46, height: 46)
                Text(initials(person.name))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(person.isMe ? .white : .primary)
            }
            Text(person.displayName(among: people))
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(width: 78)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }

    /// Small Fruchterman-Reingold-style layout, run once. "Me" is pinned centre.
    private func computeLayout(in size: CGSize) {
        guard !people.isEmpty else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ids = people.map(\.id)
        let n = ids.count

        var pos: [UUID: CGPoint] = [:]
        for (i, id) in ids.enumerated() {
            let angle = 2 * Double.pi * Double(i) / Double(n)
            pos[id] = CGPoint(x: center.x + cos(angle) * 120, y: center.y + sin(angle) * 120)
        }
        let meId = people.first { $0.isMe }?.id
        if let meId { pos[meId] = center }

        var pairs: [(UUID, UUID)] = []
        for e in relationships {
            if let a = e.subject?.id, let b = e.object?.id, a != b { pairs.append((a, b)) }
        }

        let repulsion = 9000.0
        let springLen = 92.0

        for _ in 0..<260 {
            var dx: [UUID: Double] = [:]
            var dy: [UUID: Double] = [:]

            for i in 0..<n {
                for j in (i + 1)..<n {
                    let a = ids[i], b = ids[j]
                    guard let pa = pos[a], let pb = pos[b] else { continue }
                    var ex = pa.x - pb.x
                    var ey = pa.y - pb.y
                    var dist = (ex * ex + ey * ey).squareRoot()
                    if dist < 0.01 { dist = 0.01; ex = 0.5; ey = 0.5 }
                    let force = repulsion / (dist * dist)
                    let fx = ex / dist * force
                    let fy = ey / dist * force
                    dx[a, default: 0] += fx; dy[a, default: 0] += fy
                    dx[b, default: 0] -= fx; dy[b, default: 0] -= fy
                }
            }

            for (a, b) in pairs {
                guard let pa = pos[a], let pb = pos[b] else { continue }
                let ex = pb.x - pa.x
                let ey = pb.y - pa.y
                let dist = max((ex * ex + ey * ey).squareRoot(), 0.01)
                let force = (dist - springLen) * 0.05
                let fx = ex / dist * force
                let fy = ey / dist * force
                dx[a, default: 0] += fx; dy[a, default: 0] += fy
                dx[b, default: 0] -= fx; dy[b, default: 0] -= fy
            }

            for id in ids where id != meId {
                guard var p = pos[id] else { continue }
                var mx = dx[id] ?? 0
                var my = dy[id] ?? 0
                mx += (center.x - p.x) * 0.02
                my += (center.y - p.y) * 0.02
                let mag = max((mx * mx + my * my).squareRoot(), 0.01)
                let step = min(mag, 12)
                p.x += mx / mag * step
                p.y += my / mag * step
                p.x = min(max(p.x, 46), size.width - 46)
                p.y = min(max(p.y, 60), size.height - 80)
                pos[id] = p
            }
        }
        positions = pos
    }
}
