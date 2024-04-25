//
//  StyledSlider.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 24.04.24.
//

import Foundation
import Cocoa

// Inspired by https://github.com/MonitorControl/MonitorControl
class StyledSliderCell: NSSliderCell {
    let knobFillColor = NSColor.white
    let knobFillColorTracking = NSColor(white: 0.95, alpha: 1)
    let knobStrokeColor = NSColor(white: 0.85, alpha: 1)
    
    let barFillColor = NSColor.systemGray.withAlphaComponent(0.2)
    let barStrokeColor = NSColor.systemGray.withAlphaComponent(0.5)
    let barFilledFillColor = NSColor.white
    
    let inset: CGFloat = 3.5
    let offsetX: CGFloat = -1.5
    let offsetY: CGFloat = -1.5
    
    var isTracking: Bool = false
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init() {
        super.init()
    }
    
    override func barRect(flipped: Bool) -> NSRect {
        let bar = super.barRect(flipped: flipped)
        let knob = super.knobRect(flipped: flipped)
        return NSRect(x: bar.origin.x, y: knob.origin.y, width: bar.width, height: knob.height).insetBy(dx: 0, dy: self.inset).offsetBy(dx: self.offsetX, dy: self.offsetY)
    }
    
    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        self.isTracking = true
        return super.startTracking(at: startPoint, in: controlView)
    }
    
    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        self.isTracking = false
        return super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    }
    
    override func knobRect(flipped: Bool) -> NSRect {
        let barOuterRect = barRect(flipped: flipped)
        let normalizedValue = getNormalizedSliderValue()
        
        let knobDiameter = barOuterRect.height - 1
        let knobStart = (barOuterRect.width - knobDiameter) * normalizedValue

        return NSRect(x: knobStart, y: barOuterRect.origin.y, width: knobDiameter, height: knobDiameter).offsetBy(dx: 0.5, dy: 0.5)
    }
    
    override func drawKnob(_ knobRect: NSRect) {
        let radius = knobRect.height * 0.5
        
        let knob = NSBezierPath(roundedRect: knobRect, xRadius: radius, yRadius: radius)
        if self.isTracking {
            knobFillColorTracking.setFill()
        } else {
            knobFillColor.setFill()
        }
        knob.fill()
        
        self.knobStrokeColor.setStroke()
        knob.stroke()
    }
    
    override func drawBar(inside barOuterRect: NSRect, flipped: Bool) {
        let normalizedValue = getNormalizedSliderValue()
        
        let knobDiameter = barOuterRect.height
        let radius = knobDiameter * 0.5
        let knobStart = (barOuterRect.width - knobDiameter) * normalizedValue
        
        // Bar background
        let bar = NSBezierPath(roundedRect: barOuterRect, xRadius: radius, yRadius: radius)
        self.barFillColor.setFill()
        bar.fill()
        
        // Filled bar
        let barFilledWidth = knobStart + knobDiameter
        let barFilledRect = NSRect(x: barOuterRect.origin.x, y: barOuterRect.origin.y, width: barFilledWidth, height: barOuterRect.height)
        let barFilled = NSBezierPath(roundedRect: barFilledRect, xRadius: radius, yRadius: radius)
        self.barFilledFillColor.setFill()
        barFilled.fill()
        
        self.barStrokeColor.setStroke()
        bar.stroke()
    }
    
    func getNormalizedSliderValue() -> Double {
        return (Double(self.floatValue) - self.minValue) / (self.maxValue - self.minValue)
    }
}

class StyledSlider: NSSlider {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.cell = StyledSliderCell()
    }
}
