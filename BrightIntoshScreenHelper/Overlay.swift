//
//  Overlay.swift
//  BrightIntoshScreenHelper
//

import Cocoa
import MetalKit

class Overlay: MTKView, MTKViewDelegate {
    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    private let targetHDRValue: Double = 4.0
    private let rampDuration: TimeInterval = 2.0
    
    private var commandQueue: MTLCommandQueue?
    private var rampStartDate: Date?
    private var rampStartHDRValue: Double = 1.0
    private var currentHDRValue: Double = 1.0
    
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
        
        applyExtendedDynamicRangeWants(true)
        
        if let layer = self.layer as? CAMetalLayer {
            layer.isOpaque = false
            layer.pixelFormat = .rgba16Float
            if multiplyCompositing {
                layer.compositingFilter = "multiply"
            }
            if let screen = window?.screen {
                let maxNits = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
                layer.edrMetadata = CAEDRMetadata.hdr10(minLuminance: 0.0, maxLuminance: Float(maxNits), opticalOutputScale: 1.0)
            }
        }
    }
    
    private func applyExtendedDynamicRangeWants(_ enabled: Bool) {
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.wantsExtendedDynamicRangeContent = enabled
            if let screen = window?.screen, enabled {
                let maxNits = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
                metalLayer.edrMetadata = CAEDRMetadata.hdr10(minLuminance: 0.0, maxLuminance: Float(maxNits), opticalOutputScale: 1.0)
            } else {
                metalLayer.edrMetadata = nil
            }
        }
        CATransaction.flush()
    }
    
    func nudgeExtendedDynamicRangeContent(screen: NSScreen) {
        applyExtendedDynamicRangeWants(false)
        setNeedsDisplay(bounds)
        
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self else {
                return
            }
            self.applyExtendedDynamicRangeWants(true)
            self.screenUpdate(screen: screen)
            self.setNeedsDisplay(self.bounds)
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func screenUpdate(screen: NSScreen) {
        rampStartHDRValue = 1.0
        currentHDRValue = rampStartHDRValue
        rampStartDate = Date()
        preferredFramesPerSecond = 15
        updateClearColor()
    }
    
    func draw(in view: MTKView) {
        guard let commandQueue = commandQueue,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        advanceRampIfNeeded()
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    private func advanceRampIfNeeded() {
        guard let rampStartDate else {
            return
        }
        
        let progress = min(Date().timeIntervalSince(rampStartDate) / rampDuration, 1.0)
        currentHDRValue = rampStartHDRValue + (targetHDRValue - rampStartHDRValue) * progress
        updateClearColor()
        
        if progress >= 1.0 {
            self.rampStartDate = nil
            preferredFramesPerSecond = 5
        }
    }
    
    private func updateClearColor() {
        clearColor = MTLClearColorMake(currentHDRValue, currentHDRValue, currentHDRValue, 1.0)
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
