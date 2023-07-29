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
    
    private var renderPassDescriptor: MTLRenderPassDescriptor?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    
    private var maxEdrValue: Float = 1.0
    
    private let screen: NSScreen
    
    init(frame: CGRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        
        guard let device else {
            fatalError("No metal device")
        }
        
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
        
        // Render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = currentDrawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 1, 1)
        self.renderPassDescriptor = renderPassDescriptor
        
        
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
        
        maxEdrValue = Float(screen.maximumExtendedDynamicRangeColorComponentValue)
        print(maxEdrValue)
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func screenUpdate(screen: NSScreen) {
        self.maxEdrValue = Float(screen.maximumExtendedDynamicRangeColorComponentValue)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandQueue = self.commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              let vertexBuffer = self.vertexBuffer,
              let pipelineState = self.pipelineState else {
            return
        }
        
        var fragmentColor = vector_float4(maxEdrValue, maxEdrValue, maxEdrValue, 1.0)
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(drawable.texture, index: 0)
        renderEncoder.setFragmentBytes(&fragmentColor, length: MemoryLayout.size(ofValue: fragmentColor), index: 1)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
