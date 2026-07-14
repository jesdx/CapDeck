import XCTest

final class CapDeckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettingsNavigationAndSafetyControls() {
        let app = launchApplication()
        let statusItem = app.menuBars.statusItems["CapDeck"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        statusItem.descendants(matching: .menuItem)["Settings…"].click()

        let settingsWindow = app.windows.firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        app.buttons["General"].click()
        XCTAssertTrue(app.staticTexts["Clipboard-first preset"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Show CapDeck in the menu bar"].exists)
        XCTAssertTrue(app.staticTexts["Software Updates"].exists)
        XCTAssertTrue(app.staticTexts["Current version"].exists)
        XCTAssertTrue(app.staticTexts["Automatically check for updates"].exists)
        XCTAssertTrue(app.buttons["Check for Updates…"].exists)

        app.buttons["Capture"].click()
        XCTAssertTrue(app.staticTexts["File Saving"].waitForExistence(timeout: 2))

        app.buttons["Shortcuts"].click()
        XCTAssertTrue(app.staticTexts["Global Shortcuts"].waitForExistence(timeout: 2))

        app.buttons["After Capture"].click()
        XCTAssertTrue(app.staticTexts["Clipboard"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testMenuBarProvidesCriticalCommands() {
        let app = launchApplication()
        let statusItem = app.menuBars.statusItems["CapDeck"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()

        XCTAssertTrue(app.menuItems["Capture Region"].exists)
        XCTAssertTrue(app.menuItems["Capture Window"].exists)
        XCTAssertTrue(app.menuItems["Capture Full Screen"].exists)
        XCTAssertTrue(app.menuItems["Capture History"].exists)
        XCTAssertFalse(app.menuItems["Check for Updates…"].exists)
        XCTAssertTrue(app.menuItems["Settings…"].exists)
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["CAPDECK_UI_TESTING"] = "1"
            app.launch()
        }
    }

    @MainActor
    private func launchApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CAPDECK_UI_TESTING"] = "1"
        app.launch()
        return app
    }
}
