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
    private(set) var submittedFrameCount: UInt64 = 0
    private(set) var completedFrameCount: UInt64 = 0
    private(set) var failedFrameCount: UInt64 = 0
    private(set) var lastRenderingError: String?
    private(set) var drawableFailureCount: UInt64 = 0
    private(set) var lastFrameCompletionDate: Date?
    var onFirstFrameRendered: (() -> Void)?

    var renderingDiagnostics: String {
        let lastCompletion: String
        if let lastFrameCompletionDate {
            lastCompletion = String(format: "%.2fs ago", Date().timeIntervalSince(lastFrameCompletionDate))
        } else {
            lastCompletion = "never"
        }
        return "frames submitted/completed/failed \(submittedFrameCount)/\(completedFrameCount)/\(failedFrameCount), " +
            "drawable failures \(drawableFailureCount), last successful completion \(lastCompletion), " +
            "last rendering error \(lastRenderingError ?? "none")"
    }
    
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
        guard let commandQueue = commandQueue else {
            return
        }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            drawableFailureCount += 1
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            lastRenderingError = "Could not create command buffer or render encoder"
            return
        }

        submittedFrameCount += 1
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] buffer in
            let succeeded = buffer.status == .completed
            let error = buffer.error?.localizedDescription ?? "Command buffer status \(buffer.status.rawValue)"
            DispatchQueue.main.async {
                guard let self else { return }
                guard succeeded else {
                    self.failedFrameCount += 1
                    self.lastRenderingError = error
                    return
                }
                self.completedFrameCount += 1
                self.lastFrameCompletionDate = Date()
                if !self.didRenderFirstFrame {
                    self.didRenderFirstFrame = true
                    self.onFirstFrameRendered?()
                    self.onFirstFrameRendered = nil
                }
            }
        }
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}
