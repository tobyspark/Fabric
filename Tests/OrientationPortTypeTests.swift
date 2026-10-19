import Testing
import Foundation
import Metal
import simd
@testable import Fabric
import Satin

/// Orientation: a quaternion carried as simd_float4, like Color, so it wires to
/// Vector4 and to every node that carries orientation as Vector4. It replaced a
/// simd_quatf-backed Quaternion type that wired to nothing else.
@Suite("Orientation Port Type")
struct OrientationPortTypeTests
{
    private func makeContext() -> Context?
    {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return Context(
            device: device,
            sampleCount: 1,
            colorPixelFormat: .bgra8Unorm,
            depthPixelFormat: .depth32Float,
            stencilPixelFormat: .invalid
        )
    }

    private func decoder(for context: Context) -> JSONDecoder
    {
        let decoder = JSONDecoder()
        decoder.context = DecoderContext(documentContext: context)
        return decoder
    }

    // MARK: - Ports

    @Test("Orientation ports carry simd_float4 and say they are Orientation")
    func orientationPortsAreVector4Backed()
    {
        let outlet = PortType.Orientation.makeFreshPort(name: "Orientation", kind: .Outlet)
        #expect(outlet is NodePort<simd_float4>)
        #expect(outlet.portType == .Orientation)

        let inlet = PortType.Orientation.makeFreshPort(name: "Orientation", kind: .Inlet)
        let parameterInlet = inlet as? ParameterPort<simd_float4>
        #expect(parameterInlet?.value == simd_float4(0, 0, 0, 1), "An unwired Orientation inlet rests at identity")
        #expect(inlet.portType == .Orientation)

        let arrayOutlet = PortType.Array(portType: .Orientation).makeFreshPort(name: "Orientations", kind: .Outlet)
        #expect(arrayOutlet is NodePort<ContiguousArray<simd_float4>>)
        #expect(arrayOutlet.portType == .Array(portType: .Orientation))
    }

    @Test("Orientation connects to Vector4, and through it to Color's nodes, but not to Color")
    func orientationConnectsThroughVector4()
    {
        #expect(PortType.Orientation.canConnect(to: .Vector4))
        #expect(PortType.Vector4.canConnect(to: .Orientation))
        #expect(!PortType.Orientation.canConnect(to: .Color))
        #expect(!PortType.Color.canConnect(to: .Orientation))

        #expect(PortType.Array(portType: .Orientation).canConnect(to: .Array(portType: .Vector4)))
        #expect(PortType.Array(portType: .Vector4).canConnect(to: .Array(portType: .Orientation)))
        #expect(PortType.Array(portType: .Color).canConnect(to: .Array(portType: .Vector4)))
        #expect(!PortType.Array(portType: .Orientation).canConnect(to: .Array(portType: .Color)))
        #expect(!PortType.Array(portType: .Float).canConnect(to: .Array(portType: .Int)))
    }

    @Test("Nodes set to Orientation wire to the orientation nodes")
    func orientationNodesCompose() throws
    {
        guard let context = makeContext() else { return }

        let compose = ComposeOrientationNode(context: context)
        let composeOutlet = try #require(compose.findPort(named: "outputOrientation") as Fabric.Port?)
        let blend = ValueBlendNode(context: context, portType: .Orientation)
        let source = try #require(blend.findPort(named: "inputSource") as Fabric.Port?)
        #expect(source.canConnect(to: composeOutlet))
        #expect(composeOutlet.canConnect(to: source))

        let composeArray = ComposeOrientationArrayNode(context: context)
        let composeArrayOutlet = try #require(composeArray.findPort(named: "outputOrientations") as Fabric.Port?)
        let queue = ArrayQueueNode(context: context, portType: .Orientation)
        let queueOutlet = try #require(queue.findPort(named: "outputPort") as Fabric.Port?)
        let tween = OrientationArrayTweenNode(context: context)
        let tweenTargets = try #require(tween.findPort(named: "inputTargets") as Fabric.Port?)
        #expect(queueOutlet.canConnect(to: tweenTargets))
        #expect(tweenTargets.canConnect(to: queueOutlet))
        #expect(composeArrayOutlet.portType == .Array(portType: .Vector4))
    }

    @Test("An Orientation parameter port survives a save as one")
    func orientationParameterPortRoundTrips() throws
    {
        guard let context = makeContext() else { return }

        let port = try #require(PortType.Orientation.makeFreshPort(name: "Orientation", kind: .Inlet) as? ParameterPort<simd_float4>)
        let quarterTurn = simd_quatf(angle: .pi / 2, axis: simd_float3(0, 1, 0)).vector
        port.value = quarterTurn

        let data = try JSONEncoder().encode(AnyPort(port))
        let decoded = try decoder(for: context).decode(AnyPort.self, from: data).base

        #expect(decoded is OrientationParameterPort)
        #expect(decoded.portType == .Orientation)
        #expect((decoded as? ParameterPort<simd_float4>)?.value == quarterTurn)
        #expect(decoded.id == port.id)
    }

    // MARK: - Blending and distance

    @Test("Orientation blends along the short arc; Vector4 blends per component")
    func orientationSlerps() throws
    {
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let halfTurn = simd_quatf(angle: .pi * 0.9, axis: simd_float3(0, 1, 0))
        let expected = simd_slerp(identity, halfTurn, 0.5).vector

        guard case .Vector4(let blended) = ValueBlendNode.blended(.Vector4(identity.vector), .Vector4(halfTurn.vector), amount: 0.5, as: .Orientation)
        else { Issue.record("expected an Orientation blend"); return }
        #expect(simd_distance(blended, expected) < 1e-5)
        #expect(abs(simd_length(blended) - 1) < 1e-5, "Stays a unit quaternion")

        guard case .Vector4(let mixed) = ValueBlendNode.blended(.Vector4(identity.vector), .Vector4(halfTurn.vector), amount: 0.5, as: .Vector4)
        else { Issue.record("expected a Vector4 blend"); return }
        #expect(simd_distance(mixed, simd_mix(identity.vector, halfTurn.vector, simd_float4(repeating: 0.5))) < 1e-6)

        guard case .Array(let blendedArray) = ValueBlendNode.blended(.Array([.Vector4(identity.vector)]), .Array([.Vector4(halfTurn.vector)]), amount: 0.5, as: .Array(portType: .Orientation)),
              case .Vector4(let element) = blendedArray.first
        else { Issue.record("expected an Array of Orientation blend"); return }
        #expect(simd_distance(element, expected) < 1e-5)
    }

    @Test("Orientation distance is the angle between")
    func orientationDistanceIsAngle() throws
    {
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1).vector
        let quarterTurn = simd_quatf(angle: .pi / 2, axis: simd_float3(1, 0, 0)).vector

        let angle = try #require(NumericValueOperations.distance(.Vector4(identity), .Vector4(quarterTurn), as: .Orientation, metric: .euclidean))
        #expect(abs(angle - .pi / 2) < 1e-5)
    }

    // MARK: - Documents saved with Quaternion

    @Test("A saved Quaternion type name reads back as Orientation")
    func quaternionRawValueReadsAsOrientation()
    {
        #expect(PortType(rawValue: "Quaternion") == .Orientation)
        #expect(PortType(rawValue: "Array of Quaternion") == .Array(portType: .Orientation))
        #expect(PortType(rawValue: "Dictionary of Quaternion") == .Dictionary(valueType: .Orientation))
        #expect(PortType.currentRawValue(forSaved: "Array of Quaternion") == "Array of Orientation")
        #expect(PortType.currentRawValue(forSaved: "Virtual") == "Virtual")
        #expect(PortType.currentRawValue(forSaved: "Euler") == "Euler")
    }

    @Test("A saved quaternion parameter port, which Satin cannot decode, comes back a plain Orientation port")
    func quaternionParameterPortDecodesAsPlainOrientationPort() throws
    {
        guard let context = makeContext() else { return }

        let decoded = try decoder(for: context).decode(AnyPort.self, from: Data(Self.savedQuaternionParameterPort.utf8)).base
        #expect(decoded is OrientationNodePort)
        #expect(decoded.parameter == nil)
        #expect(decoded.id == UUID(uuidString: "F92F2B0C-9DFC-482A-9BA3-6CD8FDE23C30"))
    }

    @Test("A document saved with Quaternion nodes opens with Orientation ones, wired as before")
    func quaternionDocumentOpensAsOrientation() throws
    {
        guard let context = makeContext() else { return }

        let graph = try decoder(for: context).decode(Graph.self, from: Data(Self.savedQuaternionGraph.utf8))
        #expect(graph.nodes.count == 3)

        let passThrough = try #require(graph.nodes.compactMap { $0 as? OrientationPassThroughNode }.first)
        #expect(passThrough.output.portType == .Orientation)

        let blend = try #require(graph.nodes.compactMap { $0 as? ValueBlendNode }.first)
        #expect(blend.strategy == "Orientation")
        #expect(blend.subtitle == "Orientation")
        let source = try #require(blend.findPort(named: "inputSource") as Fabric.Port?)
        #expect(source.portType == .Orientation)
        #expect(source.id == UUID(uuidString: "15E3C78A-0D9F-407D-8444-28BDD8E366AD"))
        #expect(source.connectedPorts.contains { $0 === passThrough.output }, "The pass-through still feeds Value Blend")

        let queue = try #require(graph.nodes.compactMap { $0 as? ArrayQueueNode }.first)
        #expect(queue.strategy == "Orientation")
        let queueOutlet = try #require(queue.findPort(named: "outputPort") as Fabric.Port?)
        #expect(queueOutlet.portType == .Array(portType: .Orientation))
    }

    /// What a build with the Quaternion type wrote for a quaternion shader
    /// uniform: a parameter Satin encodes as .generic and cannot decode.
    private static let savedQuaternionParameterPort = #"""
{"base":{"id":"F92F2B0C-9DFC-482A-9BA3-6CD8FDE23C30","kind":"Inlet","name":"Rotation","parameter":{"base":{"controlType":"none","defaultValue":[0,0.24740396,0,0.9689124],"description":"","id":"F92F2B0C-9DFC-482A-9BA3-6CD8FDE23C30","label":"Rotation","value":[0,0.24740396,0,0.9689124]},"type":"generic"},"published":false},"isParameterPort":true,"isProxyPort":false,"type":"Quaternion"}
"""#

    /// What a build with the Quaternion type wrote for a Quaternion pass-through
    /// wired into a Value Blend set to Quaternion, beside an Array Queue set to
    /// Quaternion.
    private static let savedQuaternionGraph = #"""
{"connections":[{"active":true,"id":"3C78CE45-2383-443B-B893-71EA69E69BC6","inletPortID":"15E3C78A-0D9F-407D-8444-28BDD8E366AD","outletPortID":"78BACDE5-E2E9-47B0-80BE-9FD59CB63FE7"}],"id":"91231B30-8573-4821-BE40-4D7100C9E958","nodeMap":[{"type":"graphics.fabric.CoreNodes/PassThroughNode<simd_quatf>","value":{"id":"52EE2C81-4CAD-4B2A-B681-F6730CA42EBD","nodeOffset":[0,0],"ports":[{"name":"input","payload":{"base":{"id":"838FD81A-BF26-4C40-BF60-D0CB5B8B5E2B","kind":"Inlet","name":"Quaternion","portDescription":"Input Quaternion","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Quaternion"}},{"name":"output","payload":{"base":{"id":"78BACDE5-E2E9-47B0-80BE-9FD59CB63FE7","kind":"Outlet","name":"Quaternion","portDescription":"Output Quaternion","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Quaternion"}}]}},{"type":"graphics.fabric.CoreNodes/ValueBlendNode","value":{"id":"764A1699-0698-4C01-ACFB-486601263D34","nodeOffset":[0,0],"ports":[{"name":"inputSource","payload":{"base":{"id":"15E3C78A-0D9F-407D-8444-28BDD8E366AD","kind":"Inlet","name":"Source","portDescription":"The value at Blend Amount 0","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Quaternion"}},{"name":"inputTarget","payload":{"base":{"id":"E9AC1A9F-7D60-45F8-81BF-D46B8496620F","kind":"Inlet","name":"Target","portDescription":"The value at Blend Amount 1","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Quaternion"}},{"name":"inputBlendAmount","payload":{"base":{"id":"6CF1065A-4B7C-4877-BD2C-CAD97127F023","kind":"Inlet","name":"Blend Amount","parameter":{"base":{"controlType":"inputfield","defaultValue":0.5,"description":"0 is Source, 1 is Target; not clamped","id":"6CF1065A-4B7C-4877-BD2C-CAD97127F023","label":"Blend Amount","max":1,"min":0,"value":0.5},"type":"float"},"portDescription":"0 is Source, 1 is Target; not clamped","published":false},"isParameterPort":true,"isProxyPort":false,"type":"Float"}},{"name":"outputValue","payload":{"base":{"id":"FA220279-B71C-4E20-BD5D-1380B22DD844","kind":"Outlet","name":"Value","portDescription":"The blended value","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Quaternion"}}],"strategy":"Quaternion"}},{"type":"graphics.fabric.CoreNodes/ArrayQueueNode","value":{"id":"1E9F5A76-FE4F-4395-AFD8-D5905ACCB172","nodeOffset":[0,0],"ports":[{"name":"inputPort","payload":{"base":{"id":"8C5C90D5-ECD3-4A84-B777-5F3603261D79","kind":"Inlet","name":"Value","portDescription":"Value to insert at the front of the queue","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Quaternion"}},{"name":"inputSizeParam","payload":{"base":{"id":"B5B15E19-F278-4287-BA9A-78E6C439A686","kind":"Inlet","name":"Size","parameter":{"base":{"controlType":"inputfield","defaultValue":0,"description":"Maximum number of elements to keep in the queue","id":"B5B15E19-F278-4287-BA9A-78E6C439A686","label":"Size","max":1,"min":0,"value":0},"type":"int"},"portDescription":"Maximum number of elements to keep in the queue","published":false},"isParameterPort":true,"isProxyPort":false,"type":"Int"}},{"name":"resetPort","payload":{"base":{"id":"C6FBC8AE-C92D-4FC8-95F2-F64D3A8B31BA","kind":"Inlet","name":"Reset","parameter":{"base":{"controlType":"button","defaultValue":false,"description":"When true, drops all queued items while maintaining capacity","id":"C6FBC8AE-C92D-4FC8-95F2-F64D3A8B31BA","label":"Reset","value":false},"type":"bool"},"portDescription":"When true, drops all queued items while maintaining capacity","published":false},"isParameterPort":true,"isProxyPort":false,"type":"Bool"}},{"name":"outputPort","payload":{"base":{"id":"078EEF9F-519A-4686-B0C1-28F2CCA3A85D","kind":"Outlet","name":"Array","portDescription":"Array containing the queued values","published":false},"isParameterPort":false,"isProxyPort":false,"type":"Array of Quaternion"}}],"strategy":"Quaternion"}}],"notes":[],"requiredPlugins":[{"id":"graphics.fabric.CoreNodes"}],"version":{"beta":{}}}
"""#
}
