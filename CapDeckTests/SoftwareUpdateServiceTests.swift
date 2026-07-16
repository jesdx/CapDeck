@testable import CapDeck
import Testing

@MainActor
struct SoftwareUpdateServiceTests {
    @Test
    func manualCheckRunsOnlyWhenTheUpdaterIsReady() {
        var checkCount = 0
        let ready = SoftwareUpdateService(
            displayVersion: "1.2.0 (Build 3)",
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            checkAction: { checkCount += 1 }
        )
        let unavailable = SoftwareUpdateService(
            displayVersion: "1.2.0 (Build 3)",
            canCheckForUpdates: false,
            automaticallyChecksForUpdates: false,
            checkAction: { checkCount += 1 }
        )

        ready.checkForUpdates()
        unavailable.checkForUpdates()

        #expect(checkCount == 1)
        #expect(ready.displayVersion == "1.2.0 (Build 3)")
    }

    @Test
    func automaticCheckPreferenceChangesOnlyOnUserTransitions() {
        var changes: [Bool] = []
        let service = SoftwareUpdateService(
            displayVersion: "1.2.0 (Build 3)",
            canCheckForUpdates: true,
            automaticallyChecksForUpdates: false,
            automaticChecksAction: { changes.append($0) }
        )

        service.setAutomaticallyChecksForUpdates(true)
        service.setAutomaticallyChecksForUpdates(true)
        service.setAutomaticallyChecksForUpdates(false)

        #expect(changes == [true, false])
        #expect(!service.automaticallyChecksForUpdates)
    }
}
