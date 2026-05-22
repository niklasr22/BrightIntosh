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
    private var didRenderFirstFrame = false
    var onFirstFrameRendered: (() -> Void)?
    
    init(frame: CGRect, multiplyCompositing: Bool = false, clearColorValue: Double = 1.6) {
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
        setClearColorValue(clearColorValue)
        preferredFramesPerSecond = 5
        
        if let layer = self.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.backgroundColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
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
        draw()
    }
    
    func setClearColorValue(_ value: Double) {
        clearColor = MTLClearColorMake(value, value, value, 1.0)
        draw()
    }
    
    func draw(in view: MTKView) {
        guard let commandQueue = commandQueue,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor),
              let drawable = view.currentDrawable else {
            return
        }
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.didRenderFirstFrame else { return }
                self.didRenderFirstFrame = true
                self.onFirstFrameRendered?()
                self.onFirstFrameRendered = nil
            }
        }
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
