import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// Registry-wide contract check for the naming checklist rule: whenever editing
/// a node's state changes its subtitle, subtitleSubject must fire. Probes the
/// string-parameter surface — the source every port-derived subtitle reads —
/// so a node that derives a title from a port without wiring feedsSubtitle()
/// fails here instead of shipping a stale canvas title.
@Suite struct SubtitleNotificationConformanceTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(device: device,
                       sampleCount: 1,
                       colorPixelFormat: .bgra8Unorm,
                       depthPixelFormat: .depth32Float,
                       stencilPixelFormat: .invalid)
    }

    /// Instantiating these spawns work unfit for tests: the local model nodes
    /// kick off an MLX model load (network), Screen Capture queries shareable
    /// content (capture permission).
    private static let skippedNodeNames: Set<String> = [
        "Local VLM Node",
        "Local LLM Node",
        "Screen Capture Provider",
    ]

    @Test func stringParameterEditsThatRenameAlsoNotify() throws
    {
        guard let context = makeContext() else { return }

        for wrapper in try NodeRegistry.shared.availableNodes
        {
            // Shader-file wrappers need a fileURL init and derive their name
            // from the file, not a parameter.
            guard wrapper.fileURL == nil,
                  !Self.skippedNodeNames.contains(wrapper.nodeClass.name),
                  let node = try? wrapper.nodeClass.initWithContext(context: context)
            else { continue }

            for port in node.inputPorts()
            {
                guard let parameter = port.parameter as? StringParameter else { continue }

                var notified = false
                let subscription = node.subtitleSubject.sink { notified = true }
                defer { subscription.cancel() }

                let before = node.subtitle
                parameter.value = before == "probe" ? "probe-2" : "probe"

                if node.subtitle != before
                {
                    #expect(notified, "\(node.canonicalName): editing '\(parameter.label)' changes subtitle without firing subtitleSubject")
                }
            }
        }
    }
}
