import XCTest
@testable import FocusMode

final class ModelTests: XCTestCase {
    func testSystemApplicationDetectionCoversFinderAndSystemURLs() {
        let finder = ProtectedApplication(
            id: "com.apple.finder",
            name: "Finder",
            bundleIdentifier: "com.apple.finder",
            url: nil,
            matchingIdentifiers: ["finder"]
        )
        let systemURL = ProtectedApplication(
            id: "com.example.system",
            name: "System App",
            bundleIdentifier: "com.example.system",
            url: URL(fileURLWithPath: "/System/Applications/System App.app"),
            matchingIdentifiers: ["system app"]
        )
        let regular = ProtectedApplication(
            id: "com.example.regular",
            name: "Regular App",
            bundleIdentifier: "com.example.regular",
            url: URL(fileURLWithPath: "/Applications/Regular App.app"),
            matchingIdentifiers: ["regular app"]
        )

        XCTAssertTrue(finder.isSystemApplication)
        XCTAssertTrue(systemURL.isSystemApplication)
        XCTAssertFalse(regular.isSystemApplication)
    }

    func testExclusionProfileDefaultsAndCodableRoundTrip() throws {
        let profile = ExclusionProfile(
            name: "Coding",
            exclusionsText: "Terminal",
            protectedApplicationIDs: ["com.apple.Terminal"]
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ExclusionProfile.self, from: data)

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(ExclusionProfile(name: "Empty").exclusionsText, "")
        XCTAssertNil(ExclusionProfile(name: "Empty").protectedApplicationIDs)
    }

    func testLocalizationUsesDefaultsAndFormatsArguments() {
        XCTAssertEqual(L10n.string("missing.key", defaultValue: "Fallback"), "Fallback")
        XCTAssertEqual(L10n.format("missing.count", defaultValue: "%ld apps", 3), "3 apps")
    }
}
