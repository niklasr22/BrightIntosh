//
//  SliderHandler.swift
//  BrightIntosh
//
//  Created by Johanna Schwarz on 21.04.24.
//

//  Adapted from https://github.com/MonitorControl/MonitorControl - Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import os.log

class SliderHandler {
    var slider: NSSlider?
    var view: NSView?
    var percentageBox: NSTextField?
    var values: [CGDirectDisplayID: Float] = [:]
    var title: String
    var icon: ClickThroughImageView?
    
    class MCSliderCell: NSSliderCell {
        let knobFillColor = NSColor(white: 1, alpha: 1)
        let knobFillColorTracking = NSColor(white: 0.8, alpha: 1)
        let knobStrokeColor = NSColor.systemGray.withAlphaComponent(0.5)
        let knobShadowColor = NSColor(white: 0, alpha: 0.03)
        let barFillColor = NSColor.systemGray.withAlphaComponent(0.2)
        let barStrokeColor = NSColor.systemGray.withAlphaComponent(0.5)
        let barFilledFillColor = NSColor(white: 1, alpha: 1)
        
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
        
        override func drawKnob(_ knobRect: NSRect) {
            guard #available(macOS 11.0, *) else {
                super.drawKnob(knobRect)
                return
            }
            // This is intentionally empty as the knob is inside the bar. Please leave it like this!
        }
        
        override func drawBar(inside aRect: NSRect, flipped: Bool) {
            guard  #available(macOS 11.0, *) else {
                super.drawBar(inside: aRect, flipped: flipped)
                return
            }
            let maxValue: Float = self.floatValue
            let minValue: Float = self.floatValue
            
            let barRadius = aRect.height * 0.5
            let bar = NSBezierPath(roundedRect: aRect, xRadius: barRadius, yRadius: barRadius)
            self.barFillColor.setFill()
            bar.fill()
            
            let barFilledWidth = (aRect.width - aRect.height) * CGFloat(maxValue) + aRect.height
            let barFilledRect = NSRect(x: aRect.origin.x, y: aRect.origin.y, width: barFilledWidth, height: aRect.height)
            let barFilled = NSBezierPath(roundedRect: barFilledRect, xRadius: barRadius, yRadius: barRadius)
            self.barFilledFillColor.setFill()
            barFilled.fill()
            
            let knobMinX = aRect.origin.x + (aRect.width - aRect.height) * CGFloat(minValue)
            let knobMaxX = aRect.origin.x + (aRect.width - aRect.height) * CGFloat(maxValue)
            let knobRect = NSRect(x: knobMinX, y: aRect.origin.y, width: aRect.height + CGFloat(knobMaxX - knobMinX), height: aRect.height).insetBy(dx: CGFloat(0), dy: 0)
            let knobRadius = knobRect.height * 0.5
            
            let knobAlpha = CGFloat(max(0, min(1, (minValue - 0.08) * 5)))
            for i in 1 ... 3 {
                let knobShadow = NSBezierPath(roundedRect: knobRect.offsetBy(dx: CGFloat(-1 * 2 * i), dy: 0), xRadius: knobRadius, yRadius: knobRadius)
                self.knobShadowColor.withAlphaComponent(self.knobShadowColor.alphaComponent * knobAlpha).setFill()
                knobShadow.fill()
            }
            
            let knob = NSBezierPath(roundedRect: knobRect, xRadius: knobRadius, yRadius: knobRadius)
            (self.isTracking ? self.knobFillColorTracking : self.knobFillColor).withAlphaComponent(knobAlpha).setFill()
            knob.fill()
            
            self.knobStrokeColor.withAlphaComponent(self.knobStrokeColor.alphaComponent * knobAlpha).setStroke()
            knob.stroke()
            self.barStrokeColor.setStroke()
            bar.stroke()
        }
    }
    
    class MCSlider: NSSlider {
        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.cell = MCSliderCell()
        }
        
        //  Credits for this class go to @thompsonate - https://github.com/thompsonate/Scrollable-NSSlider
        override func scrollWheel(with event: NSEvent) {
            guard self.isEnabled else { return }
            let range = Float(self.maxValue - self.minValue)
            var delta = Float(0)
            if self.isVertical, self.sliderType == .linear {
                delta = Float(event.deltaY)
            } else if self.userInterfaceLayoutDirection == .rightToLeft {
                delta = Float(event.deltaY + event.deltaX)
            } else {
                delta = Float(event.deltaY - event.deltaX)
            }
            if event.isDirectionInvertedFromDevice {
                delta *= -1
            }
            let increment = range * delta / 100
            let value = self.floatValue + increment
            self.floatValue = value
            self.sendAction(self.action, to: self.target)
        }
    }
    
    class ClickThroughImageView: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            subviews.first { subview in subview.hitTest(point) != nil
            }
        }
    }
    
    public init(title: String = "") {
        self.title = title
        //let slider = SliderHandler.MCSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(valueChanged))
        //let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(valueChanged))
        let slider = NSSlider(value: 1.2, minValue: 0, maxValue: 1.6, target: self, action: #selector(valueChanged))
        self.slider = slider
        if #available(macOS 11.0, *) {
            /*slider.frame.size.width = 180
            slider.frame.origin = NSPoint(x: 15, y: 5)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: slider.frame.width + 30 +  38, height: slider.frame.height + 14))
            view.frame.origin = NSPoint(x: 12, y: 0)
            let icon = SliderHandler.ClickThroughImageView()
            icon.contentTintColor = NSColor.black.withAlphaComponent(0.6)
            icon.frame = NSRect(x: view.frame.origin.x + 6.5, y: view.frame.origin.y + 13, width: 15, height: 15)
            icon.imageAlignment = .alignCenter
            view.addSubview(slider)
            //view.addSubview(icon)
            self.icon = icon
            
            let percentageBox = NSTextField(frame: NSRect(x: 15 + slider.frame.size.width - 2, y: 17, width: 40, height: 12))
            self.setupPercentageBox(percentageBox)
            self.percentageBox = percentageBox
            view.addSubview(percentageBox)*/
            let sliderContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 35))
            let horizontalPadding: CGFloat = 5.0
            let sliderWidth = sliderContainerView.frame.width - (2 * horizontalPadding)
            let sliderHeight = 30.0
            let sliderX = (sliderContainerView.frame.width - sliderWidth) / 2
            let sliderY = (sliderContainerView.frame.height - sliderWidth) / 2
            
            slider.target = self
            slider.frame = NSRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
            slider.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            sliderContainerView.addSubview(slider)
            sliderContainerView.autoresizingMask = [.width]
            
            self.view = sliderContainerView
        } else {
            slider.frame.size.width = 180
            slider.frame.origin = NSPoint(x: 15, y: 5)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: slider.frame.width + 30 + 38, height: slider.frame.height + 10))
            view.addSubview(slider)
            let percentageBox = NSTextField(frame: NSRect(x: 15 + slider.frame.size.width - 2, y: 18, width: 40, height: 12))
            self.setupPercentageBox(percentageBox)
            self.percentageBox = percentageBox
            view.addSubview(percentageBox)
            
            self.view = view
        }
        slider.maxValue = 1
    }
    
    func setupPercentageBox(_ percentageBox: NSTextField) {
        percentageBox.font = NSFont.systemFont(ofSize: 12)
        percentageBox.isEditable = false
        percentageBox.isBordered = false
        percentageBox.drawsBackground = false
        percentageBox.alignment = .right
        percentageBox.alphaValue = 0.7
    }
    
    @objc func valueChanged(slider: NSSlider) {
        print("Value changed to \(slider.floatValue)")
    }
    
    func setValue(_ value: Float) {
        if let slider = self.slider {
            var sumVal: Float = 0
            var maxVal: Float = 0
            var minVal: Float = 1
            var num = 0
            for key in self.values.keys {
                if let val = values[key] {
                    sumVal += val
                    maxVal = max(maxVal, val)
                    minVal = min(minVal, val)
                    num += 1
                }
            }
            // let average = sumVal / Float(num)
            slider.floatValue = value
            if self.percentageBox == self.percentageBox {
                self.percentageBox?.stringValue = "" + String(Int(value * 100)) + "%"
            }
        }
    }
}
