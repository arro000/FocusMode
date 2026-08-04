import XCTest
@testable import FocusMode

private let performanceManagerDefaultsKeys = [
    "isUltraPerformanceModeEnabled",
    "ultraPerformanceModeSavedApplications",
    "ultraPerformanceModeCustomExclusions",
    "ultraPerformanceModeExclusionProfiles",
    "ultraPerformanceModeSelectedProfile",
    "focusModeDefaultProtectedApplications",
    "focusModeDefaultExclusionsText"
]

private func clearPerformanceManagerDefaults() {
    let defaults = UserDefaults.standard
    for key in performanceManagerDefaultsKeys {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class PerformanceManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearPerformanceManagerDefaults()
    }

    override func tearDown() {
        clearPerformanceManagerDefaults()
        super.tearDown()
    }

    func testInitializesGeneralProfileAndBuiltInProtectedApplications() {
        let manager = PerformanceManager()

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.selectedProfileID, manager.profiles[0].id)
        XCTAssertEqual(manager.selectedProfileName, "General")
        XCTAssertTrue(manager.availableApplications.contains { $0.id == "com.apple.finder" })
        XCTAssertTrue(manager.defaultProtectedApplicationIDs.contains("com.apple.finder"))
    }

    func testProfileLifecycleAndSelection() {
        let manager = PerformanceManager()
        let originalProfileID = manager.selectedProfileID

        manager.addProfile()
        let newProfileID = manager.selectedProfileID
        XCTAssertEqual(manager.profiles.count, 2)
        XCTAssertNotEqual(newProfileID, originalProfileID)
        XCTAssertEqual(manager.selectedProfileName, "New profile")

        manager.updateProfileName("Writing", for: newProfileID)
        manager.updateProfileExclusions("Notes, com.example.Editor", for: newProfileID)
        XCTAssertEqual(manager.selectedProfileName, "Writing")
        XCTAssertEqual(manager.profiles.last?.exclusionsText, "Notes, com.example.Editor")

        manager.selectProfile(originalProfileID)
        XCTAssertEqual(manager.selectedProfileID, originalProfileID)
        manager.deleteProfile(newProfileID)
        XCTAssertEqual(manager.profiles.count, 1)
    }

    func testDeletingSelectedProfileSelectsThePreviousProfile() {
        let manager = PerformanceManager()
        let firstProfileID = manager.selectedProfileID

        manager.addProfile()
        let secondProfileID = manager.selectedProfileID
        manager.deleteProfile(secondProfileID)

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.selectedProfileID, firstProfileID)
    }

    func testProfileProtectionCanBeSelectedAndDeselected() {
        let manager = PerformanceManager()
        let profileID = manager.selectedProfileID
        let application = try! XCTUnwrap(manager.availableApplications.first { $0.id == "org.mozilla.firefox" })

        XCTAssertFalse(manager.isProfileProtected(application, in: profileID))
        manager.setProfileProtected(true, application: application, in: profileID)
        XCTAssertTrue(manager.isProfileProtected(application, in: profileID))

        manager.setProfileProtected(false, application: application, in: profileID)
        XCTAssertFalse(manager.isProfileProtected(application, in: profileID))
    }

    func testProfileExclusionsAreCaseInsensitiveAndRemovedWhenDeselected() {
        let manager = PerformanceManager()
        let profileID = manager.selectedProfileID
        let application = try! XCTUnwrap(manager.availableApplications.first { $0.id == "org.mozilla.firefox" })

        manager.updateProfileExclusions(" FIREFOX, keep-me ", for: profileID)
        XCTAssertTrue(manager.isProfileProtected(application, in: profileID))

        manager.setProfileProtected(false, application: application, in: profileID)
        XCTAssertEqual(manager.profiles[0].exclusionsText, "keep-me")
    }

    func testDefaultProtectionAndCustomExclusionsPersistWhenDisabled() {
        let manager = PerformanceManager()
        let application = try! XCTUnwrap(manager.availableApplications.first { $0.id == "org.mozilla.firefox" })

        manager.setDefaultProtected(false, for: application.id)
        manager.updateDefaultExclusionsText("custom.app")

        XCTAssertFalse(manager.isDefaultProtected(application))
        XCTAssertEqual(manager.defaultExclusionsText, "custom.app")

        let reloadedManager = PerformanceManager()
        XCTAssertFalse(reloadedManager.isDefaultProtected(application))
        XCTAssertEqual(reloadedManager.defaultExclusionsText, "custom.app")
    }

    func testOperationsAreIgnoredForUnknownProfilesOrApplications() {
        let manager = PerformanceManager()
        let unknownProfileID = UUID()
        let unknownApplication = ProtectedApplication(
            id: "com.example.unknown",
            name: "Unknown",
            bundleIdentifier: "com.example.unknown",
            url: nil,
            matchingIdentifiers: ["com.example.unknown"]
        )

        manager.selectProfile(unknownProfileID)
        manager.updateProfileName("Ignored", for: unknownProfileID)
        manager.updateProfileExclusions("Ignored", for: unknownProfileID)
        manager.setProfileProtected(true, application: unknownApplication, in: unknownProfileID)
        manager.setDefaultProtected(true, for: unknownApplication.id)

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.profiles[0].name, "General")
        XCTAssertFalse(manager.defaultProtectedApplicationIDs.contains(unknownApplication.id))
        XCTAssertFalse(manager.isProfileProtected(unknownApplication, in: unknownProfileID))
    }

    func testReloadsPersistedProfilesAndKeepsAValidSelectedProfile() {
        let manager = PerformanceManager()
        let originalProfileID = manager.selectedProfileID

        manager.addProfile()
        let addedProfileID = manager.selectedProfileID
        manager.updateProfileName("Meetings", for: addedProfileID)

        let reloadedManager = PerformanceManager()
        XCTAssertEqual(reloadedManager.profiles.count, 2)
        XCTAssertEqual(reloadedManager.selectedProfileID, addedProfileID)
        XCTAssertEqual(reloadedManager.selectedProfileName, "Meetings")

        reloadedManager.selectProfile(originalProfileID)
        XCTAssertEqual(reloadedManager.selectedProfileID, originalProfileID)
    }

    func testCannotDeleteOnlyProfile() {
        let manager = PerformanceManager()
        let profileID = manager.selectedProfileID

        manager.deleteProfile(profileID)

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.selectedProfileID, profileID)
    }

}
