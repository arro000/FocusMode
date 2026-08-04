import AppKit
import Foundation

private struct SavedApplication: Codable, Identifiable {
    let id: String
    let name: String
    let applicationURL: URL
}

struct ExclusionProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var exclusionsText: String
    var protectedApplicationIDs: Set<String>?

    init(
        id: UUID = UUID(),
        name: String,
        exclusionsText: String = "",
        protectedApplicationIDs: Set<String>? = nil
    ) {
        self.id = id
        self.name = name
        self.exclusionsText = exclusionsText
        self.protectedApplicationIDs = protectedApplicationIDs
    }
}

struct ProtectedApplication: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let url: URL?
    let matchingIdentifiers: Set<String>

    var isSystemApplication: Bool {
        id == "com.apple.finder" || url?.path.hasPrefix("/System/") == true
    }
}

@MainActor
final class PerformanceManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var savedApplicationsCount: Int
    @Published private(set) var profiles: [ExclusionProfile]
    @Published private(set) var selectedProfileID: UUID
    @Published private(set) var availableApplications: [ProtectedApplication]
    @Published private(set) var defaultProtectedApplicationIDs: Set<String>
    @Published private(set) var defaultExclusionsText: String

    private enum StorageKey {
        static let isEnabled = "isUltraPerformanceModeEnabled"
        static let savedApplications = "ultraPerformanceModeSavedApplications"
        static let customExclusions = "ultraPerformanceModeCustomExclusions"
        static let exclusionProfiles = "ultraPerformanceModeExclusionProfiles"
        static let selectedProfile = "ultraPerformanceModeSelectedProfile"
        static let defaultProtectedApplications = "focusModeDefaultProtectedApplications"
        static let defaultExclusionsText = "focusModeDefaultExclusionsText"
    }

    private static let builtInProtectedApplications: [ProtectedApplication] = [
        ProtectedApplication(
            id: "com.apple.finder",
            name: "Finder",
            bundleIdentifier: "com.apple.finder",
            url: nil,
            matchingIdentifiers: ["com.apple.finder", "finder"]
        ),
        ProtectedApplication(
            id: "org.mozilla.firefox",
            name: "Firefox",
            bundleIdentifier: "org.mozilla.firefox",
            url: nil,
            matchingIdentifiers: ["org.mozilla.firefox", "firefox"]
        ),
        ProtectedApplication(
            id: "net.kovidgoyal.kitty",
            name: "kitty",
            bundleIdentifier: "net.kovidgoyal.kitty",
            url: nil,
            matchingIdentifiers: ["net.kovidgoyal.kitty", "kitty"]
        ),
        ProtectedApplication(
            id: "com.microsoft.teams2",
            name: "Microsoft Teams",
            bundleIdentifier: "com.microsoft.teams2",
            url: nil,
            matchingIdentifiers: ["com.microsoft.teams2", "com.microsoft.teams", "msteams", "microsoft teams"]
        ),
        ProtectedApplication(
            id: "com.eset.endpointsecurity",
            name: "ESET Endpoint Security",
            bundleIdentifier: "com.eset.endpointsecurity",
            url: nil,
            matchingIdentifiers: ["com.eset.endpointsecurity", "eset endpoint security", "eset endpoint security agent"]
        ),
        ProtectedApplication(
            id: "com.fortinet.forticlient",
            name: "FortiClient",
            bundleIdentifier: "com.fortinet.forticlient",
            url: nil,
            matchingIdentifiers: ["com.fortinet.forticlient", "forticlient"]
        ),
        ProtectedApplication(
            id: "ollama",
            name: "Ollama",
            bundleIdentifier: nil,
            url: nil,
            matchingIdentifiers: ["ollama"]
        ),
        ProtectedApplication(
            id: "omlx",
            name: "omlx",
            bundleIdentifier: nil,
            url: nil,
            matchingIdentifiers: ["omlx"]
        ),
        ProtectedApplication(
            id: "lm studio",
            name: "LM Studio",
            bundleIdentifier: nil,
            url: nil,
            matchingIdentifiers: ["lm studio"]
        )
    ]

    private var pendingTerminations: [pid_t: SavedApplication] = [:]

    private var savedApplications: [SavedApplication] {
        get {
            guard let data = UserDefaults.standard.data(forKey: StorageKey.savedApplications),
                  let applications = try? JSONDecoder().decode([SavedApplication].self, from: data) else {
                return []
            }
            return applications
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: StorageKey.savedApplications)
            savedApplicationsCount = newValue.count
        }
    }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: StorageKey.isEnabled)
        let defaults = UserDefaults.standard
        defaultProtectedApplicationIDs = Set(
            defaults.stringArray(forKey: StorageKey.defaultProtectedApplications)
                ?? Self.builtInProtectedApplications.map(\.id)
        )
        defaultExclusionsText = defaults.string(forKey: StorageKey.defaultExclusionsText) ?? ""
        availableApplications = Self.builtInProtectedApplications

        let savedData = UserDefaults.standard.data(forKey: StorageKey.savedApplications)
        let restoredApplications = (savedData.flatMap { try? JSONDecoder().decode([SavedApplication].self, from: $0) }) ?? []
        savedApplicationsCount = restoredApplications.count

        let loadedProfiles: [ExclusionProfile]
        if let profileData = defaults.data(forKey: StorageKey.exclusionProfiles),
           let storedProfiles = try? JSONDecoder().decode([ExclusionProfile].self, from: profileData),
           !storedProfiles.isEmpty {
            loadedProfiles = storedProfiles
        } else {
            // Keep the old single exclusion list when upgrading an existing installation.
            loadedProfiles = [
                ExclusionProfile(
                    name: L10n.string("profile.general", defaultValue: "General"),
                    exclusionsText: defaults.string(forKey: StorageKey.customExclusions) ?? ""
                )
            ]
            if let data = try? JSONEncoder().encode(loadedProfiles) {
                defaults.set(data, forKey: StorageKey.exclusionProfiles)
            }
        }

        profiles = loadedProfiles
        let storedProfileID = defaults.string(forKey: StorageKey.selectedProfile).flatMap(UUID.init)
        let profileID = loadedProfiles.contains { $0.id == storedProfileID }
            ? (storedProfileID ?? loadedProfiles[0].id)
            : loadedProfiles[0].id
        selectedProfileID = profileID
        defaults.set(selectedProfileID.uuidString, forKey: StorageKey.selectedProfile)

        let applicationsStillClosed = restoredApplications.filter { !isAlreadyRunning($0) }

        // An app can decline a quit request. Do not retain it for a later restore.
        if applicationsStillClosed.count != restoredApplications.count {
            savedApplications = applicationsStillClosed
        }

        refreshAvailableApplications()
    }

    var selectedProfileName: String {
        selectedProfile?.name ?? L10n.string("profile.general", defaultValue: "General")
    }

    var applicationsToCloseCount: Int {
        NSWorkspace.shared.runningApplications.filter(shouldClose).count
    }

    func selectProfile(_ profileID: UUID) {
        guard !isEnabled, profiles.contains(where: { $0.id == profileID }) else {
            return
        }

        selectedProfileID = profileID
        UserDefaults.standard.set(profileID.uuidString, forKey: StorageKey.selectedProfile)
    }

    func addProfile() {
        let profile = ExclusionProfile(name: L10n.string("profile.new", defaultValue: "New profile"))
        profiles.append(profile)
        saveProfiles()
        selectProfile(profile.id)
    }

    func updateProfileName(_ name: String, for profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        profiles[index].name = name
        saveProfiles()
    }

    func updateProfileExclusions(_ text: String, for profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        profiles[index].exclusionsText = text
        saveProfiles()
    }

    func isProfileProtected(_ application: ProtectedApplication, in profileID: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == profileID }) else {
            return false
        }

        return profile.protectedApplicationIDs?.contains(application.id) == true
            || !exclusionsSet(from: profile.exclusionsText).isDisjoint(with: application.matchingIdentifiers)
    }

    func setProfileProtected(
        _ isProtected: Bool,
        application: ProtectedApplication,
        in profileID: UUID
    ) {
        guard !isEnabled,
              let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        var applicationIDs = profiles[index].protectedApplicationIDs ?? []
        if isProtected {
            applicationIDs.insert(application.id)
        } else {
            applicationIDs.remove(application.id)
            let remainingExclusions = profiles[index].exclusionsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !application.matchingIdentifiers.contains($0.lowercased()) }
            profiles[index].exclusionsText = remainingExclusions.joined(separator: ", ")
        }
        profiles[index].protectedApplicationIDs = applicationIDs
        saveProfiles()
    }

    func refreshAvailableApplications() {
        var applications = Self.builtInProtectedApplications
        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for directory in applicationDirectories where FileManager.default.fileExists(atPath: directory.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                addApplication(at: url, to: &applications)
            }
        }

        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular {
            if let url = application.bundleURL, !url.path.hasPrefix("/System/") {
                addApplication(at: url, to: &applications)
            }
        }

        availableApplications = applications.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func isDefaultProtected(_ application: ProtectedApplication) -> Bool {
        defaultProtectedApplicationIDs.contains(application.id)
    }

    func setDefaultProtected(_ isProtected: Bool, for applicationID: String) {
        guard !isEnabled, availableApplications.contains(where: { $0.id == applicationID }) else {
            return
        }

        if isProtected {
            defaultProtectedApplicationIDs.insert(applicationID)
        } else {
            defaultProtectedApplicationIDs.remove(applicationID)
        }
        UserDefaults.standard.set(Array(defaultProtectedApplicationIDs).sorted(), forKey: StorageKey.defaultProtectedApplications)
    }

    func updateDefaultExclusionsText(_ text: String) {
        guard !isEnabled else {
            return
        }

        defaultExclusionsText = text
        UserDefaults.standard.set(text, forKey: StorageKey.defaultExclusionsText)
    }

    func deleteProfile(_ profileID: UUID) {
        guard profiles.count > 1,
              let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        profiles.remove(at: index)
        saveProfiles()

        if selectedProfileID == profileID {
            selectProfile(profiles[max(0, index - 1)].id)
        }
    }

    func toggle() {
        isEnabled ? disable() : enable()
    }

    func cleanUp() {
        pendingTerminations = [:]

        for application in NSWorkspace.shared.runningApplications where shouldClose(application) {
            application.terminate()
        }

        // This mode deliberately does not retain anything for a later restore.
        savedApplications = []
        isEnabled = false
        UserDefaults.standard.set(false, forKey: StorageKey.isEnabled)
    }

    private func enable() {
        pendingTerminations = [:]

        for application in NSWorkspace.shared.runningApplications where shouldClose(application) {
            guard let applicationURL = application.bundleURL, application.terminate() else {
                continue
            }

            pendingTerminations[application.processIdentifier] =
                SavedApplication(
                    id: application.bundleIdentifier ?? applicationURL.path,
                    name: application.localizedName ?? applicationURL.deletingPathExtension().lastPathComponent,
                    applicationURL: applicationURL
                )
        }

        savedApplications = []
        isEnabled = true
        UserDefaults.standard.set(true, forKey: StorageKey.isEnabled)
        monitorTerminationRequests()
    }

    private func disable() {
        let applicationsToRestore = savedApplications
        pendingTerminations = [:]

        for application in applicationsToRestore {
            guard !isAlreadyRunning(application) else {
                continue
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            Task {
                try? await NSWorkspace.shared.openApplication(at: application.applicationURL, configuration: configuration)
            }
        }

        savedApplications = []
        isEnabled = false
        UserDefaults.standard.set(false, forKey: StorageKey.isEnabled)
    }

    private func monitorTerminationRequests() {
        Task { @MainActor [weak self] in
            for _ in 0..<300 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)

                guard let self, self.isEnabled else {
                    return
                }

                self.recordTerminatedApplications()
                if self.pendingTerminations.isEmpty {
                    return
                }
            }
        }
    }

    private func recordTerminatedApplications() {
        let runningProcessIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let terminatedProcessIDs = pendingTerminations.keys.filter { !runningProcessIDs.contains($0) }

        guard !terminatedProcessIDs.isEmpty else {
            return
        }

        var applicationsToRestore = savedApplications
        for processID in terminatedProcessIDs {
            guard let application = pendingTerminations.removeValue(forKey: processID) else {
                continue
            }
            applicationsToRestore.append(application)
        }
        savedApplications = applicationsToRestore
    }

    private func isAlreadyRunning(_ savedApplication: SavedApplication) -> Bool {
        let savedURL = savedApplication.applicationURL.resolvingSymlinksInPath()

        return NSWorkspace.shared.runningApplications.contains { application in
            guard !application.isTerminated else {
                return false
            }

            if application.bundleIdentifier == savedApplication.id {
                return true
            }

            return application.bundleURL?.resolvingSymlinksInPath() == savedURL
        }
    }

    private func shouldClose(_ application: NSRunningApplication) -> Bool {
        guard application.activationPolicy == .regular,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !application.isTerminated else {
            return false
        }

        let identifiers = [application.bundleIdentifier, application.localizedName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        return !identifiers.contains { exclusions($0) }
    }

    private func exclusions(_ identifier: String) -> Bool {
        defaultExclusionIdentifiers.contains(identifier)
            || defaultCustomExclusions.contains(identifier)
            || profileExclusionIdentifiers.contains(identifier)
            || customExclusions.contains(identifier)
    }

    private var defaultExclusionIdentifiers: Set<String> {
        Set(
            availableApplications
                .filter { defaultProtectedApplicationIDs.contains($0.id) }
                .flatMap(\.matchingIdentifiers)
        )
    }

    private var defaultCustomExclusions: Set<String> {
        exclusionsSet(from: defaultExclusionsText)
    }

    private var customExclusions: Set<String> {
        exclusionsSet(from: selectedProfile?.exclusionsText ?? "")
    }

    private var profileExclusionIdentifiers: Set<String> {
        let applicationIDs = selectedProfile?.protectedApplicationIDs ?? []
        return Set(
            availableApplications
                .filter { applicationIDs.contains($0.id) }
                .flatMap(\.matchingIdentifiers)
        )
    }

    private var selectedProfile: ExclusionProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }

        UserDefaults.standard.set(data, forKey: StorageKey.exclusionProfiles)
    }

    private func exclusionsSet(from text: String) -> Set<String> {
        Set(
            text
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private func addApplication(at url: URL, to applications: inout [ProtectedApplication]) {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else {
            return
        }

        let normalizedIdentifier = bundleIdentifier.lowercased()
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        let normalizedName = name.lowercased()
        if let knownApplication = Self.builtInProtectedApplications.first(where: {
            $0.matchingIdentifiers.contains(normalizedIdentifier)
                || $0.matchingIdentifiers.contains(normalizedName)
        }),
           let knownIndex = applications.firstIndex(where: { $0.id == knownApplication.id }) {
            let known = applications[knownIndex]
            applications[knownIndex] = ProtectedApplication(
                id: known.id,
                name: known.name,
                bundleIdentifier: bundleIdentifier,
                url: url,
                matchingIdentifiers: known.matchingIdentifiers
            )
            return
        }

        if applications.contains(where: { $0.id.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            return
        }

        applications.append(
            ProtectedApplication(
                id: bundleIdentifier,
                name: name,
                bundleIdentifier: bundleIdentifier,
                url: url,
                matchingIdentifiers: [normalizedIdentifier, name.lowercased()]
            )
        )
    }
}
