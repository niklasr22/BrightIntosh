//
//  BrightnessDiagnosticHistory.swift
//  BrightIntosh
//

import Foundation

@MainActor
enum BrightnessDiagnosticHistory {
    private static let maximumEventCount = 50
    private static let startDate = Date()
    private static var previousEventDate = startDate
    private static var nextEventNumber = 1
    private static var events: [String] = []

    static func record(_ message: String) {
        let now = Date()
        let event = String(
            format: "[%03d +%.2fs, +%.2fs] %@",
            nextEventNumber,
            now.timeIntervalSince(startDate),
            now.timeIntervalSince(previousEventDate),
            message
        )
        nextEventNumber += 1
        previousEventDate = now
        events.append(event)

        if events.count > maximumEventCount {
            events.removeFirst(events.count - maximumEventCount)
        }
    }

    static func append(to report: inout String) {
        report += "Brightness event history (oldest to newest, up to \(maximumEventCount) events):\n"
        if events.isEmpty {
            report += " - No events recorded\n"
        } else {
            report += events.joined(separator: "\n") + "\n"
        }
    }
}
