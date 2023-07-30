//
//  Overlay.swift
//  BrightIntosh
//
//  Created by Niklas Rousset 12.07.23.
//

import Cocoa
import MetalKit

class Overlay: MTKView, MTKViewDelegate {
    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    
    private var commandQueue: MTLCommandQueue?
    private var commandBuffer: MTLCommandBuffer?
    
    private var renderPassDescriptor: MTLRenderPassDescriptor?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    
    private var fragmentColor = vector_float4(1.0, 1.0, 1.0, 1.0)
    
    private let screen: NSScreen
    
    init(frame: CGRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        
        guard let device else {
            fatalError("No metal device")
        }
        
        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)
        
        commandQueue = device.makeCommandQueue()
        
        if commandQueue == nil {
            fatalError("Could not create command queue")
        }
        
        guard let fragmentShader = device.makeDefaultLibrary()?.makeFunction(name: "fragmentShader") else {
            fatalError("Could not create fragment shader function")
        }
        guard let vertexShader = device.makeDefaultLibrary()?.makeFunction(name: "vertexShader") else {
            fatalError("Could not create vertex shader function")
        }
        
        delegate = self
        framebufferOnly = false
        preferredFramesPerSecond = screen.maximumFramesPerSecond
        colorPixelFormat = .rgba16Float
        colorspace = colorSpace
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        
        if let layer = self.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.displaySyncEnabled = true
            layer.pixelFormat = .rgba16Float
            layer.compositingFilter = "multiply"
        }
        
        // Pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexShader
        pipelineDescriptor.fragmentFunction = fragmentShader
        pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormat.rgba16Float
        
        
        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            fatalError("Failed to create Metal Pipeline state")
        }
        self.pipelineState = pipelineState
        
        
        // Vertex buffer
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
             -1.0, 1.0, 0.0, 1.0,
             1.0,  -1.0, 0.0, 1.0,
             1.0,  1.0, 0.0, 1.0,
        ]
        
        self.vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])!
        
        screenUpdate(screen: screen)
        
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func screenUpdate(screen: NSScreen) {
        let maxEdrValue = Float(screen.maximumExtendedDynamicRangeColorComponentValue)
        fragmentColor = vector_float4(maxEdrValue, maxEdrValue, maxEdrValue, 1.0)
    }
    
    func draw(in view: MTKView) {
        guard let commandQueue = commandQueue,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              let vertexBuffer = self.vertexBuffer,
              let pipelineState = self.pipelineState else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBytes(&fragmentColor, length: MemoryLayout.size(ofValue: fragmentColor), index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
