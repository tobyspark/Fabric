import Testing
import Foundation
import Metal
@testable import Fabric
import Satin

/// End-to-end title pipeline: the inspector edits a node's Parameter, whose
/// publisher pushes into the ParameterPort, whose feedsSubtitle() wiring
/// fires subtitleSubject, which the NodeViewModel sinks on the main queue into
/// the titleLabel the canvas title draws.
@Suite struct TitleRefreshHarnessTests
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

    // Suspending frees the main queue so the view model's
    // receive(on: .main) sink can deliver.
    private func pumpMainQueue() async
    {
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test @MainActor func blendTitleFollowsInspectorModeEdit() async throws
    {
        guard let context = makeContext() else { return }
        let node = try BlendNode(context: context, fileURL: Bundle.module.url(forResource: "Additive", withExtension: "metal", subdirectory: "EffectsTwoChannel/Mix")!)
        let vm = NodeViewModel(node: node)

        #expect(vm.titleLabel == "Additive")

        // The inspector's dropdown edits the Parameter, not the port.
        (node.inputMode.parameter as! StringParameter).value = "Multiply"
        await pumpMainQueue()

        #expect(node.subtitle == "Multiply")
        #expect(vm.titleLabel == "Multiply")
        #expect(node.debugDescription == "Blend (Multiply)")
    }

    @Test @MainActor func operatorTitleFollowsInspectorEdit() async throws
    {
        guard let context = makeContext() else { return }
        let node = NumberUnaryOperator(context: context)
        let vm = NodeViewModel(node: node)

        #expect(vm.titleLabel == "Sine")

        (node.inputParam.parameter as! StringParameter).value = "Cosine"
        await pumpMainQueue()

        #expect(vm.titleLabel == "Cosine")
    }

    @Test @MainActor func labelMatchingCanonicalNameIsSuppressed() throws
    {
        guard let context = makeContext() else { return }
        let node = NumberUnaryOperator(context: context)
        let vm = NodeViewModel(node: node)

        vm.userName = node.canonicalName
        #expect(vm.titleLabel == nil)
    }

    @Test @MainActor func emptySubtitleAndUserNameAreAbsence() async throws
    {
        guard let context = makeContext() else { return }
        let node = NumberUnaryOperator(context: context)
        let vm = NodeViewModel(node: node)

        (node.inputParam.parameter as! StringParameter).value = ""
        await pumpMainQueue()
        #expect(vm.titleLabel == nil)
        #expect(node.debugDescription == node.canonicalName)

        node.userName = ""
        #expect(node.userName == nil)
        #expect(node.title == node.canonicalName)
    }
}
