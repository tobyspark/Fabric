//
//  GraphExecution.swift
//  v
//
//  Created by Anton Marini on 4/27/24.
//

import SwiftUI
import Metal
import Satin
import simd

// Graph Execution Engine
public class GraphRenderer : MetalViewRenderer
{
    private var lastGraphExecutionTime = Date.timeIntervalSinceReferenceDate
    private var executionCount = 0
    public var context:Context!
    
    private let renderer:Renderer
    private let scene = Object()
    public var clearColor:simd_float4 = simd_float4(0.0, 0.0, 0.0, 1.0)
    
    public let graph:Graph
    
    public init(context:Context, graph:Graph)
    {
        self.context = context
        self.renderer = Renderer(context: context)
        self.graph = graph
        print("Init Graph Execution Engine")
    }
    
    public func disableExecution(graph:Graph)
    {
        let executionContext = self.currentGraphExecutionContext()

        self.graph.nodes.forEach({ $0.disableExecution(context: executionContext) })
    }
    
    public func enableExecution(graph:Graph)
    {
        let executionContext = self.currentGraphExecutionContext()

        self.graph.nodes.forEach({ $0.enableExecution(context: executionContext) })
    }
    
    // MARK: - Rendering
    public func execute(graph:Graph,
                        executionContext:GraphExecutionContext,
                        renderPassDescriptor: MTLRenderPassDescriptor,
                        commandBuffer:MTLCommandBuffer)
    {
        self.executionCount += 1
        
        var nodesWeAreExecuting:[any NodeProtocol] = []

        // TODO: Sort
        let objectsNodesToProcess: [any NodeProtocol] = graph.nodes.filter( {
            $0.nodeType == .Object || $0.nodeType == .Light || $0.nodeType == .Mesh || $0.nodeType == .Camera
        })

        // TODO: Stupid
        let objectNodesToRender = objectsNodesToProcess.filter( { $0.nodeType != .Camera })
        let cameraNodes = objectsNodesToProcess.filter( { $0.nodeType == .Camera })
        
        for objectNode in objectsNodesToProcess// + subgraphNodes
        {
            let _ = processGraph(graph:graph,
                                 node: objectNode,
                                 executionContext:executionContext,
                                 renderPassDescriptor: renderPassDescriptor,
                                 commandBuffer: commandBuffer,
                                 nodesWeAreExecuting:&nodesWeAreExecuting)
        }
        
        
        let cameraObjects = cameraNodes.compactMap( { ($0 as? any ObjectNodeProtocol)?.object as? Camera } )
        
        let sceneObjects = objectNodesToRender.compactMap( { ($0 as? any ObjectNodeProtocol)?.object } )
        
        // In theory this early bails if object is already in the scene?
        self.scene.add(sceneObjects)
        
        self.renderer.draw(renderPassDescriptor: renderPassDescriptor,
                           commandBuffer: commandBuffer,
                           scene: scene,
                           cameras: cameraObjects,
                           viewports: [self.renderer.viewport])
        
        //            self.scene.removeAll()
        
        
    }

    private func processGraph(graph:Graph,
                              node: any NodeProtocol,
                              executionContext:GraphExecutionContext,
                              renderPassDescriptor: MTLRenderPassDescriptor,
                              commandBuffer: MTLCommandBuffer,
                              nodesWeAreExecuting:inout  [any NodeProtocol ],
                              pruningNodes:[any NodeProtocol] = [])
    {
        
        // get the connection for
        let inputNodes = node.inputNodes()
        for node in inputNodes
        {
            processGraph(graph: graph,
                         node: node,
                         executionContext:executionContext,
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer,
                         nodesWeAreExecuting: &nodesWeAreExecuting,
                         pruningNodes:inputNodes)
        }
        
        if node.isDirty
        {
            node.execute(context: executionContext,
                         renderPassDescriptor: renderPassDescriptor,
                         commandBuffer: commandBuffer)
            
            // TODO: This should be handled inside of the base node class no?
            node.markDirty()
//            node.lastEvaluationTime = executionContext.timing.time
        }
    }
    
    public override func draw(renderPassDescriptor: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer)
    {
        let executionContext = self.currentGraphExecutionContext()
        self.execute(graph:self.graph,
                     executionContext: executionContext,
                     renderPassDescriptor: renderPassDescriptor,
                     commandBuffer: commandBuffer)
        
        self.lastGraphExecutionTime = executionContext.timing.time
    }
    
    override public func resize(size: (width: Float, height: Float), scaleFactor: Float)
    {
        self.graph.nodes.forEach { $0.resize(size: size, scaleFactor: scaleFactor)}
    }
    
    private func currentGraphExecutionContext() -> GraphExecutionContext
    {
        let currentRenderTime = Date.timeIntervalSinceReferenceDate
        
        // TODO: This becomes more semantically correct later
        let timing = GraphExecutionTiming(time: currentRenderTime,
                                          deltaTime: currentRenderTime - self.lastGraphExecutionTime,
                                          displayTime: currentRenderTime,
                                          systemTime: currentRenderTime,
                                          frameNumber: self.executionCount)
        
        return GraphExecutionContext(context: self.context,
                                     timing: timing,
                                     iterationInfo: nil,
                                     eventInfo: nil)
    }
            
//            if let inputFrame = self.frameCache.cachedFrame(fromNode: source, atTime: time)
//            {
//                inputFrames.append(inputFrame)
//            }
//            else
//            {
//                if let _ = nodesWeAreExecuting.firstIndex(of: source)
//                {
//                    // Check if the node has already been processed in the current frame
//                    if let cachedFrame = self.frameCache.cachedFrame(fromNode: source, atTime: self.lastGraphExecutionTime)
//                    {
//                        inputFrames.append(cachedFrame)
//                    }
//                    else
//                    {
//                        print("feedback loop cache miss")
//                    }
//                }
//                else
//                {
//                    if let inputFrame = processGraph(graph: graph,
//                                                     node: source,
//                                                     withCommandBuffer:withCommandBuffer,
//                                                     atTime: time,
//                                                     nodesWeAreExecuting: &nodesWeAreExecuting,
//                                                     pruningConnections:connections)
//                    {
//                        self.frameCache.cacheFrame(frame: inputFrame,
//                                                   fromNode: source,
//                                                   atTime: time)
//                        
//                        inputFrames.append(inputFrame)
//                    }
//                }
//            }
            
//        }
//
//        node.preProcess(atTime:time)
//
//        if let outputFrame = node.process(inputFrames: inputFrames,
//                                          onCommandBuffer: withCommandBuffer,
//                                          atTime: time)
//        {
//            self.frameCache.cacheFrame(frame: outputFrame,
//                                       fromNode: node,
//                                       atTime: time)
//            return outputFrame
//        }
//        
//        return nil
//    }
}

