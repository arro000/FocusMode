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

    init(id: UUID = UUID(), name: String, exclusionsText: String = "") {
        self.id = id
        self.name = name
        self.exclusionsText = exclusionsText
    }
}

@MainActor
final class PerformanceManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var savedApplicationsCount: Int
    @Published private(set) var profiles: [ExclusionProfile]
    @Published private(set) var selectedProfileID: UUID

    private enum StorageKey {
        static let isEnabled = "isUltraPerformanceModeEnabled"
        static let savedApplications = "ultraPerformanceModeSavedApplications"
        static let customExclusions = "ultraPerformanceModeCustomExclusions"
        static let exclusionProfiles = "ultraPerformanceModeExclusionProfiles"
        static let selectedProfile = "ultraPerformanceModeSelectedProfile"
    }

    // Keep the legacy keys so existing profiles and restorable sessions survive the rebrand.
    private let defaultExclusions: Set<String> = [
        "com.apple.finder", "finder",
        "org.mozilla.firefox", "firefox",
        "net.kovidgoyal.kitty", "kitty",
        "com.microsoft.teams2", "com.microsoft.teams", "msteams", "microsoft teams",
        "com.eset.endpointsecurity", "eset endpoint security", "eset endpoint security agent",
        "com.fortinet.forticlient", "forticlient",
        "ollama", "omlx", "lm studio"
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
        let savedData = UserDefaults.standard.data(forKey: StorageKey.savedApplications)
        let restoredApplications = (savedData.flatMap { try? JSONDecoder().decode([SavedApplication].self, from: $0) }) ?? []
        savedApplicationsCount = restoredApplications.count

        let defaults = UserDefaults.standard
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
        defaultExclusions.contains(identifier) || customExclusions.contains(identifier)
    }

    private var customExclusions: Set<String> {
        Set(
            (selectedProfile?.exclusionsText ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
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
}
