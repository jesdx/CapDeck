@testable import CapDeck
import Foundation
import Testing

@MainActor
struct ScreenCapturePermissionServiceTests {
    @Test
    func presentsTheSystemRequestOnlyOnceAcrossServiceInstances() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "ScreenCapturePermissionServiceTests.\(UUID().uuidString)")
        )
        var requestCount = 0
        let request: () -> Bool = {
            requestCount += 1
            return false
        }
        let first = ScreenCapturePermissionService(
            defaults: defaults,
            preflightAccess: { false },
            requestSystemAccess: request
        )

        #expect(first.requestAccess() == .systemPromptPresented)

        let relaunched = ScreenCapturePermissionService(
            defaults: defaults,
            preflightAccess: { false },
            requestSystemAccess: request
        )
        #expect(relaunched.requestAccess() == .previouslyRequested)
        #expect(requestCount == 1)
    }

    @Test
    func authorizedAccessNeverPresentsTheSystemRequest() throws {
        let defaults = try #require(
            UserDefaults(suiteName: "ScreenCapturePermissionServiceTests.\(UUID().uuidString)")
        )
        var requestCount = 0
        let service = ScreenCapturePermissionService(
            defaults: defaults,
            preflightAccess: { true },
            requestSystemAccess: {
                requestCount += 1
                return false
            }
        )

        #expect(service.requestAccess() == .authorized)
        #expect(requestCount == 0)
    }
}
