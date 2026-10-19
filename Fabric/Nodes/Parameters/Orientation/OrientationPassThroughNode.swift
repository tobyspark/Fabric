//
//  OrientationPassThroughNode.swift
//  Fabric
//

import Foundation
import Satin
import simd
import Metal

/// Patching utility node for Orientation ports. Orientation shares simd_float4
/// with Vector4, so `PassThroughNode<simd_float4>` would give Vector4 ports.
public class OrientationPassThroughNode: Node
{
    override public class var name: String { "Orientation" }
    override public class var nodeType: Node.NodeType { .Utility }
    override public class var nodeExecutionMode: Node.ExecutionMode { .Provider }
    override public class var nodeTimeMode: Node.TimeMode { .None }
    override public class var nodeDescription: String { "Patching utility for Orientation." }

    // If an instance has connections on its input port, it should be considered a Processor.
    override public var nodeExecutionMode: Node.ExecutionMode { self.input.connections.isEmpty ? .Provider : .Processor }

    // Ports
    override public class func registerPorts(context: Context) -> [(name: String, port: Port)] {
        let ports = super.registerPorts(context: context)

        return ports +
        [
            ("input", PortType.Orientation.makeFreshPort(name: "Orientation", kind: .Inlet, description: "Input orientation, as a quaternion (X, Y, Z, W)")),
            ("output", PortType.Orientation.makeFreshPort(name: "Orientation", kind: .Outlet, description: "Output orientation, as a quaternion (X, Y, Z, W)")),
        ]
    }

    // Port Proxy
    public var input: NodePort<simd_float4> { port(named: "input") }
    public var output: NodePort<simd_float4> { port(named: "output") }

    override public func execute(renderer:GraphRenderer,
                                 executionInfo:GraphExecutionInfo,
                                 renderPassDescriptor: MTLRenderPassDescriptor,
                                 commandBuffer: MTLCommandBuffer)
    throws
    {
        if self.input.valueDidChange
        {
            self.output.send(self.input.value)
        }
    }
}
