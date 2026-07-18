import SwiftUI
import SwiftData
import SceneKit
import simd

/// A 3D, zoomable/orbitable relationship graph (SceneKit) — people as spheres,
/// relationships as edges, anchored on "Me". Pinch to zoom, drag to orbit, tap a
/// node to open the person. Native, no dependencies — scales as the graph grows.
struct PeopleGraph3DView: View {
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var relationships: [PersonRelationship]
    @State private var selectedID: UUID?

    var body: some View {
        SceneKitGraph(people: people, relationships: relationships) { id in
            selectedID = id
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) {
            Text(relationships.isEmpty ? "Pinch to zoom · drag to orbit · tap a person. Add relationships to connect the graph."
                                        : "Pinch to zoom · drag to orbit · tap a person.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 10)
        }
        .navigationDestination(item: $selectedID) { id in
            if let person = people.first(where: { $0.id == id }) {
                PersonDetailView(person: person)
            }
        }
    }
}

// MARK: - SceneKit host

private struct SceneKitGraph: UIViewRepresentable {
    let people: [Person]
    let relationships: [PersonRelationship]
    let onSelect: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true          // pinch-zoom, drag-orbit, two-finger pan
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X

        let scene = SCNScene()
        view.scene = scene
        rebuild(in: scene)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = 500
        camera.position = SCNVector3(0, 0, 55)
        scene.rootNode.addChildNode(camera)
        view.pointOfView = camera

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view
        context.coordinator.signature = signature
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        // Rebuild when the graph's shape changes (people/edges added or removed).
        if context.coordinator.signature != signature, let scene = uiView.scene {
            rebuild(in: scene)
            context.coordinator.signature = signature
        }
    }

    private var signature: Int {
        var hasher = Hasher()
        hasher.combine(people.count)
        hasher.combine(relationships.count)
        for p in people { hasher.combine(p.id) }
        return hasher.finalize()
    }

    // MARK: Scene construction

    private func rebuild(in scene: SCNScene) {
        scene.rootNode.childNodes
            .filter { ($0.name?.hasPrefix("node:") ?? false) || ($0.name?.hasPrefix("label:") ?? false) || $0.name == "edges" }
            .forEach { $0.removeFromParentNode() }

        let positions = computeLayout()

        for person in people {
            let pos = positions[person.id] ?? SCNVector3Zero

            let sphere = SCNSphere(radius: person.isMe ? 1.4 : 1.0)
            let mat = SCNMaterial()
            mat.diffuse.contents = person.isMe ? UIColor.systemBlue : UIColor(white: 0.82, alpha: 1)
            sphere.materials = [mat]
            let node = SCNNode(geometry: sphere)
            node.name = "node:\(person.id.uuidString)"
            node.position = pos
            scene.rootNode.addChildNode(node)

            scene.rootNode.addChildNode(labelNode(for: person, at: pos))
        }

        var vertices: [SCNVector3] = []
        for edge in relationships {
            guard let a = edge.subject?.id, let b = edge.object?.id,
                  let p1 = positions[a], let p2 = positions[b] else { continue }
            vertices.append(p1); vertices.append(p2)
        }
        if !vertices.isEmpty {
            let source = SCNGeometrySource(vertices: vertices)
            let indices = (0..<vertices.count).map { UInt32($0) }
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geo = SCNGeometry(sources: [source], elements: [element])
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(white: 0.55, alpha: 0.7)
            m.lightingModel = .constant
            geo.materials = [m]
            let edgeNode = SCNNode(geometry: geo)
            edgeNode.name = "edges"
            scene.rootNode.addChildNode(edgeNode)
        }
    }

    private func labelNode(for person: Person, at pos: SCNVector3) -> SCNNode {
        let text = SCNText(string: person.name, extrusionDepth: 0)
        text.font = .systemFont(ofSize: 4, weight: .medium)
        text.flatness = 0.4
        let tmat = SCNMaterial()
        tmat.diffuse.contents = UIColor.white
        tmat.lightingModel = .constant
        text.materials = [tmat]

        let label = SCNNode(geometry: text)
        let bb = text.boundingBox
        label.pivot = SCNMatrix4MakeTranslation((bb.min.x + bb.max.x) / 2, (bb.min.y + bb.max.y) / 2, 0)
        label.scale = SCNVector3(0.4, 0.4, 0.4)
        label.position = SCNVector3(pos.x, pos.y - (person.isMe ? 2.6 : 2.1), pos.z)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        label.constraints = [billboard]
        label.name = "label:\(person.id.uuidString)"
        return label
    }

    // MARK: 3D force-directed layout (the 2D sim extended to Z)

    private func computeLayout() -> [UUID: SCNVector3] {
        let ids = people.map(\.id)
        let n = ids.count
        guard n > 0 else { return [:] }

        var pos: [UUID: SIMD3<Float>] = [:]
        let golden = Float.pi * (3 - sqrt(Float(5)))
        let radius: Float = 18
        for (i, id) in ids.enumerated() {
            if n == 1 { pos[id] = .zero; continue }
            let y = 1 - Float(i) / Float(n - 1) * 2
            let ring = sqrt(max(0, 1 - y * y))
            let theta = golden * Float(i)
            pos[id] = SIMD3(cos(theta) * ring * radius, y * radius, sin(theta) * ring * radius)
        }
        let meId = people.first { $0.isMe }?.id
        if let meId { pos[meId] = .zero }

        var pairs: [(UUID, UUID)] = []
        for e in relationships {
            if let a = e.subject?.id, let b = e.object?.id, a != b { pairs.append((a, b)) }
        }

        let repulsion: Float = 420
        let springLen: Float = 14

        for _ in 0..<220 {
            var disp: [UUID: SIMD3<Float>] = [:]

            for i in 0..<n {
                for j in (i + 1)..<n {
                    let a = ids[i], b = ids[j]
                    guard let pa = pos[a], let pb = pos[b] else { continue }
                    var d = pa - pb
                    var dist = simd_length(d)
                    if dist < 0.01 { d = SIMD3(0.1, 0.1, 0.1); dist = simd_length(d) }
                    let dir = d / dist
                    let f = repulsion / (dist * dist)
                    disp[a, default: .zero] += dir * f
                    disp[b, default: .zero] -= dir * f
                }
            }

            for (a, b) in pairs {
                guard let pa = pos[a], let pb = pos[b] else { continue }
                let d = pb - pa
                let dist = max(simd_length(d), 0.01)
                let dir = d / dist
                let f = (dist - springLen) * 0.1
                disp[a, default: .zero] += dir * f
                disp[b, default: .zero] -= dir * f
            }

            for id in ids where id != meId {
                guard var p = pos[id] else { continue }
                var m = disp[id] ?? .zero
                m += (SIMD3<Float>.zero - p) * 0.02   // gravity toward centre
                let mag = max(simd_length(m), 0.01)
                let step = min(mag, 1.6)
                p += (m / mag) * step
                pos[id] = p
            }
        }

        return pos.mapValues { SCNVector3($0.x, $0.y, $0.z) }
    }

    // MARK: Tap → open person

    final class Coordinator: NSObject {
        var onSelect: (UUID) -> Void
        weak var scnView: SCNView?
        var signature: Int = 0

        init(onSelect: @escaping (UUID) -> Void) { self.onSelect = onSelect }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, name.hasPrefix("node:"),
                       let id = UUID(uuidString: String(name.dropFirst(5))) {
                        onSelect(id)
                        return
                    }
                    node = current.parent
                }
            }
        }
    }
}
