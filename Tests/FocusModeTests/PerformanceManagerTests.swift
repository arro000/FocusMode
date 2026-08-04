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

private struct SavedApplicationFixture: Codable {
    let id: String
    let name: String
    let applicationURL: URL
}

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

    func testMigratesLegacyExclusionsWhenProfilesAreMissing() {
        UserDefaults.standard.set(" Terminal, com.example.Editor ", forKey: "ultraPerformanceModeCustomExclusions")

        let manager = PerformanceManager()

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.profiles[0].exclusionsText, " Terminal, com.example.Editor ")
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "ultraPerformanceModeExclusionProfiles"))
    }

    func testFallsBackToGeneralProfileForEmptyStoredProfiles() throws {
        let emptyProfiles = try JSONEncoder().encode([ExclusionProfile]())
        UserDefaults.standard.set(emptyProfiles, forKey: "ultraPerformanceModeExclusionProfiles")
        UserDefaults.standard.set("Legacy", forKey: "ultraPerformanceModeCustomExclusions")

        let manager = PerformanceManager()

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.selectedProfileName, "General")
        XCTAssertEqual(manager.profiles[0].exclusionsText, "Legacy")
    }

    func testFallsBackToFirstStoredProfileForUnknownSelection() throws {
        let first = ExclusionProfile(name: "First")
        let second = ExclusionProfile(name: "Second")
        let profiles = try JSONEncoder().encode([first, second])
        UserDefaults.standard.set(profiles, forKey: "ultraPerformanceModeExclusionProfiles")
        UserDefaults.standard.set(UUID().uuidString, forKey: "ultraPerformanceModeSelectedProfile")

        let manager = PerformanceManager()

        XCTAssertEqual(manager.profiles.map(\.name), ["First", "Second"])
        XCTAssertEqual(manager.selectedProfileID, first.id)
        XCTAssertEqual(manager.selectedProfileName, "First")
    }

    func testLoadsValidSavedApplicationsAndIgnoresCorruptData() throws {
        let fixture = SavedApplicationFixture(
            id: "com.example.not-running-\(UUID().uuidString)",
            name: "Not Running",
            applicationURL: URL(fileURLWithPath: "/Applications/DefinitelyNotRunning.app")
        )
        UserDefaults.standard.set(
            try JSONEncoder().encode([fixture]),
            forKey: "ultraPerformanceModeSavedApplications"
        )

        let manager = PerformanceManager()

        XCTAssertEqual(manager.savedApplicationsCount, 1)

        UserDefaults.standard.set(Data("invalid".utf8), forKey: "ultraPerformanceModeSavedApplications")
        let reloadedManager = PerformanceManager()
        XCTAssertEqual(reloadedManager.savedApplicationsCount, 0)
    }

    func testOperationsThatRequireDisabledModeAreIgnoredWhenEnabled() {
        UserDefaults.standard.set(true, forKey: "isUltraPerformanceModeEnabled")
        let manager = PerformanceManager()
        let originalProfileID = manager.selectedProfileID
        let application = try! XCTUnwrap(manager.availableApplications.first { $0.id == "org.mozilla.firefox" })

        manager.addProfile()
        let addedProfileID = manager.profiles.last!.id
        manager.selectProfile(addedProfileID)
        manager.setProfileProtected(true, application: application, in: originalProfileID)
        manager.setDefaultProtected(false, for: application.id)
        manager.updateDefaultExclusionsText("ignored")

        XCTAssertEqual(manager.selectedProfileID, originalProfileID)
        XCTAssertFalse(manager.isProfileProtected(application, in: originalProfileID))
        XCTAssertTrue(manager.isDefaultProtected(application))
        XCTAssertEqual(manager.defaultExclusionsText, "")
    }

    func testDefaultProtectionCanBeEnabledAndDisabled() {
        let manager = PerformanceManager()
        let application = try! XCTUnwrap(manager.availableApplications.first { $0.id == "org.mozilla.firefox" })

        manager.setDefaultProtected(true, for: application.id)
        XCTAssertTrue(manager.isDefaultProtected(application))

        manager.setDefaultProtected(false, for: application.id)
        XCTAssertFalse(manager.isDefaultProtected(application))
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "focusModeDefaultProtectedApplications"), ["com.apple.finder", "net.kovidgoyal.kitty", "ollama", "omlx", "com.eset.endpointsecurity", "com.fortinet.forticlient", "com.microsoft.teams2", "lm studio"].sorted())
    }

    func testDeletingTheFirstSelectedProfileSelectsTheNewFirstProfile() {
        let manager = PerformanceManager()
        let firstProfileID = manager.selectedProfileID

        manager.addProfile()
        let secondProfileID = manager.selectedProfileID
        manager.selectProfile(firstProfileID)
        manager.deleteProfile(firstProfileID)

        XCTAssertEqual(manager.profiles.count, 1)
        XCTAssertEqual(manager.selectedProfileID, secondProfileID)
    }

    func testDisablingEnabledModeWithoutSavedApplicationsClearsState() {
        UserDefaults.standard.set(true, forKey: "isUltraPerformanceModeEnabled")
        let manager = PerformanceManager()

        XCTAssertTrue(manager.isEnabled)
        manager.toggle()

        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.savedApplicationsCount, 0)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "isUltraPerformanceModeEnabled"), false)
    }

    func testApplicationsToCloseCountIsAvailable() {
        let manager = PerformanceManager()

        XCTAssertGreaterThanOrEqual(manager.applicationsToCloseCount, 0)
    }

}
