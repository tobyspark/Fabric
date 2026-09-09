import Foundation
import Metal
import Testing
@testable import Fabric
import Satin

/// The one list of subgraph node types that Embed Selection In and any other
/// "which kind of subgraph" choice draw from: derived from the registry, so a
/// plugin's subgraph subclass appears alongside the core ones.
@Suite("Subgraph Node Types")
struct SubgraphNodeTypesTests
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

    @Test("The registry lists every SubgraphNode subclass it holds, and nothing else")
    func registryListsSubgraphTypes() throws
    {
        let registry = try NodeRegistry.shared
        let types = registry.subgraphNodeTypes

        let classNames = types.map { String(describing: $0.subgraphClass) }
        #expect(classNames.contains("SubgraphNode"))
        #expect(classNames.contains("DeferredSubgraphNode"))
        #expect(classNames.contains("IteratorNode"))
        #expect(classNames.contains("EnvironmentNode"))
        #expect(types.allSatisfy { $0.wrapper.nodeClass == $0.subgraphClass })

        let expectedCount = registry.availableNodes.filter { $0.nodeClass is SubgraphNode.Type }.count
        #expect(types.count == expectedCount)
        #expect(types.map(\.name) == types.map(\.wrapper.nodeName))
    }

    @Test("The registry's node list is the plugin loader's, not a snapshot")
    func availableNodesAreLive() throws
    {
        let registry = try NodeRegistry.shared
        let loaded = PluginLoader.shared.pluginNodeWrappers

        #expect(registry.availableNodes.count == loaded.count)
        #expect(zip(registry.availableNodes, loaded).allSatisfy { $0.id == $1.id })
    }

    @Test("A selection can be embedded in every registered subgraph type")
    func everySubgraphTypeEmbeds() throws
    {
        guard let context = makeContext() else { return }
        let registry = try NodeRegistry.shared

        for type in registry.subgraphNodeTypes
        {
            let graph = Graph(context: context)
            let node = NumberBinaryOperator(context: context)
            graph.addNode(node)

            let container = try graph.createSubgraph(from: [node], centeredOn: node, usingClass: type.subgraphClass)

            #expect(Swift.type(of: container) == type.subgraphClass, "\(type.name)")
            #expect(container.subGraph.nodes.contains { $0 === node }, "\(type.name)")
        }
    }
}
