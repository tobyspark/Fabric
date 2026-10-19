//
//  OrientationPorts.swift
//  Fabric
//

import Foundation
import simd

// Orientation shares simd_float4 with Vector4 and Color, so the Swift type alone
// would read back as .Vector4; these ports declare .Orientation themselves.

public final class OrientationNodePort: NodePort<simd_float4>
{
    @ObservationIgnored override public var portType: PortType { .Orientation }
}

public final class OrientationArrayNodePort: NodePort<ContiguousArray<simd_float4>>
{
    @ObservationIgnored override public var portType: PortType { .Array(portType: .Orientation) }
}

/// An Orientation inlet holding a value of its own when unwired, edited as
/// X, Y, Z, W. Unlike Color, no control type marks it, so the port says so.
public final class OrientationParameterPort: ParameterPort<simd_float4>
{
    @ObservationIgnored override public var portType: PortType { .Orientation }
}
