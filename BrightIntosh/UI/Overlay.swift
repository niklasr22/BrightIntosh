//
//  Overlay.swift
//  BrightIntosh
//
//  Created by Niklas Rousset 12.07.23.
//

import Cocoa
import MetalKit

class Overlay: MTKView, MTKViewDelegate {
    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    
    private var commandQueue: MTLCommandQueue?
    
    private var fragmentColor = vector_float4(1.0, 1.0, 1.0, 1.0)
    
    init(frame: CGRect, multiplyCompositing: Bool = false) {
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
        
        delegate = self
        colorPixelFormat = .rgba16Float
        colorspace = colorSpace
        clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
        preferredFramesPerSecond = 5
        
        if let layer = self.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.pixelFormat = .rgba16Float
            if multiplyCompositing {
                layer.compositingFilter = "multiply"
            }
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func screenUpdate(screen: NSScreen) {
        let maxEdrValue = screen.maximumExtendedDynamicRangeColorComponentValue
        let maxRenderedEdrValue = screen.maximumReferenceExtendedDynamicRangeColorComponentValue
        let factor = max(maxEdrValue / max(maxRenderedEdrValue, 1.0) - 1.0, 1.0)
        clearColor = MTLClearColorMake(factor, factor, factor, 1.0)
    }
    
    func setMaxFrameRate(screen: NSScreen) {
        preferredFramesPerSecond = screen.maximumFramesPerSecond
    }
    
    func setHDRBrightness(colorValue: Double, screen: NSScreen) {
        let maxEdrValue = screen.maximumExtendedDynamicRangeColorComponentValue
        let percentage = (colorValue - 1.0) / 0.6
        let newColor = ((maxEdrValue - 1.0) * percentage) + 1.0
        clearColor = MTLClearColorMake(newColor, newColor, newColor, 1.0)
    }
    
    func draw(in view: MTKView) {
        guard let commandQueue = commandQueue,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
