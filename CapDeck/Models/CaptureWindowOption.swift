import CoreGraphics
import Foundation

struct CaptureWindowOption: Identifiable, Equatable, Sendable {
    let id: CGWindowID
    let applicationName: String
    let windowTitle: String

    var displayName: String {
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title == applicationName {
            return applicationName
        }
        return "\(applicationName) — \(title)"
    }
}
