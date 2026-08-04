import XCTest
@testable import FocusMode

final class ApplicationOrderingTests: XCTestCase {
    func testSelectedApplicationsComeFirstAndRemainingApplicationsStayAlphabetical() {
        let applications = [
            application(id: "com.example.zebra", name: "Zebra"),
            application(id: "com.example.alpha", name: "Alpha"),
            application(id: "com.example.bravo", name: "bravo"),
            application(id: "com.example.charlie", name: "Charlie")
        ]

        let result = applicationsForDisplay(
            applications,
            search: "",
            isSelected: { $0.id == "com.example.zebra" || $0.id == "com.example.bravo" }
        )

        XCTAssertEqual(result.map(\.name), ["bravo", "Zebra", "Alpha", "Charlie"])
    }

    func testSearchMatchesNameOrBundleIdentifierAndTrimsWhitespace() {
        let applications = [
            application(id: "com.example.notes", name: "Notes"),
            application(id: "com.example.browser", name: "Browser"),
            application(id: "com.example.editor", name: "Editor")
        ]

        let byName = applicationsForDisplay(applications, search: "  note  ", isSelected: { _ in false })
        let byIdentifier = applicationsForDisplay(applications, search: "BROWSER", isSelected: { _ in false })

        XCTAssertEqual(byName.map(\.id), ["com.example.notes"])
        XCTAssertEqual(byIdentifier.map(\.id), ["com.example.browser"])
    }

    func testSystemApplicationsAreExcludedAndEmptySearchReturnsAllConfigurableApps() {
        let applications = [
            application(id: "com.apple.finder", name: "Finder"),
            application(id: "com.example.user", name: "User App"),
            ProtectedApplication(
                id: "com.example.system",
                name: "System App",
                bundleIdentifier: "com.example.system",
                url: URL(fileURLWithPath: "/System/Applications/System App.app"),
                matchingIdentifiers: ["com.example.system"]
            )
        ]

        let result = applicationsForDisplay(applications, search: "", isSelected: { _ in false })

        XCTAssertEqual(result.map(\.id), ["com.example.user"])
    }

    func testSameNamesUseIdentifierAsDeterministicTieBreaker() {
        let applications = [
            application(id: "com.example.z", name: "Same"),
            application(id: "com.example.a", name: "Same")
        ]

        let result = applicationsForDisplay(applications, search: "", isSelected: { _ in false })

        XCTAssertEqual(result.map(\.id), ["com.example.a", "com.example.z"])
    }

    private func application(id: String, name: String) -> ProtectedApplication {
        ProtectedApplication(
            id: id,
            name: name,
            bundleIdentifier: id,
            url: nil,
            matchingIdentifiers: [id, name.lowercased()]
        )
    }
}
