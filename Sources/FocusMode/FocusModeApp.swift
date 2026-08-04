import AppKit
import SwiftUI

@main
struct FocusModeApp: App {
    @StateObject private var manager = PerformanceManager()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(systemName: manager.isEnabled ? "scope" : "circle.dotted.circle")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(manager: manager)
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var manager: PerformanceManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("menu.title", defaultValue: "FocusMode"))
                    .font(.headline)
                Text(manager.isEnabled
                     ? L10n.string("menu.status.enabled", defaultValue: "FocusMode is active")
                     : L10n.string("menu.status.disabled", defaultValue: "Choose how to close open apps"))
                    .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("profile.label", defaultValue: "Profile"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker(L10n.string("profile.label", defaultValue: "Profile"), selection: Binding(
                    get: { manager.selectedProfileID },
                    set: { manager.selectProfile($0) }
                )) {
                    ForEach(manager.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .disabled(manager.isEnabled)
            }

            VStack(spacing: 10) {
                MenuBarActionCard(
                    title: manager.isEnabled
                        ? L10n.string("toggle.disable.title", defaultValue: "Disable and restore")
                        : L10n.string("toggle.enable.title", defaultValue: "Close and save session"),
                    subtitle: manager.isEnabled
                        ? L10n.format(
                            "toggle.restore.subtitle",
                            defaultValue: "Reopens %ld saved apps",
                            manager.savedApplicationsCount
                        )
                        : L10n.format(
                            "toggle.enable.subtitle",
                            defaultValue: "Applies \"%@\" and lets you resume later",
                            manager.selectedProfileName
                        ),
                    systemImage: manager.isEnabled ? "arrow.uturn.backward.circle.fill" : "square.and.arrow.down.fill",
                    tint: .accentColor,
                    action: manager.toggle
                )

                MenuBarActionCard(
                    title: L10n.string("cleanup.title", defaultValue: "Clean up everything"),
                    subtitle: manager.isEnabled
                        ? L10n.string("cleanup.subtitle.enabled", defaultValue: "Closes apps and discards the saved session")
                        : L10n.string("cleanup.subtitle.disabled", defaultValue: "Closes apps without saving a session"),
                    systemImage: "trash.circle.fill",
                    tint: .orange,
                    action: confirmCleanup
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
                Text(L10n.format(
                    "apps.considered",
                    defaultValue: "Apps considered: %ld",
                    manager.applicationsToCloseCount
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()

            HStack {
                Button(action: showSettings) {
                    Label(L10n.string("settings.title", defaultValue: "Settings..."), systemImage: "gear")
                }
                Spacer()
                Button(L10n.string("quit", defaultValue: "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private func confirmCleanup() {
        let alert = NSAlert()
        alert.messageText = L10n.string("cleanup.alert.title", defaultValue: "Clean up everything?")
        alert.informativeText = L10n.format(
            "cleanup.alert.message",
            defaultValue: "%ld apps will be closed. Unsaved changes may require confirmation, and this action does not create a restorable session.",
            manager.applicationsToCloseCount
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("cleanup.alert.confirm", defaultValue: "Clean up and close"))
        alert.addButton(withTitle: L10n.string("cancel", defaultValue: "Cancel"))

        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            manager.cleanUp()
        }
    }

    private func showSettings() {
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main

        openSettings()
        focusSettingsWindow(on: screen)
    }

    private func focusSettingsWindow(on screen: NSScreen?, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApplication.shared.windows.first(where: {
                $0.canBecomeKey && $0.styleMask.contains(.titled) && $0.level == .normal
            }) else {
                if attempt < 10 {
                    focusSettingsWindow(on: screen, attempt: attempt + 1)
                }
                return
            }

            if let screen {
                let visibleFrame = screen.visibleFrame
                window.setFrameOrigin(NSPoint(
                    x: visibleFrame.midX - window.frame.width / 2,
                    y: visibleFrame.midY - window.frame.height / 2
                ))
            }

            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

private struct MenuBarActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private enum SettingsDestination: Hashable {
    case behavior
    case profile(UUID)
}

struct SettingsView: View {
    @ObservedObject var manager: PerformanceManager
    @State private var destination: SettingsDestination?
    @State private var profileName = ""
    @State private var excludedApplications = ""
    @State private var defaultExclusionsText = ""

    init(manager: PerformanceManager) {
        self.manager = manager
        _destination = State(initialValue: .profile(manager.selectedProfileID))
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $destination) {
                    Section(L10n.string("settings.profiles.section", defaultValue: "Profiles")) {
                        ForEach(manager.profiles) { profile in
                            Label(profile.name, systemImage: "person.crop.square")
                                .tag(SettingsDestination.profile(profile.id))
                        }
                    }

                    Section {
                        Label(
                            L10n.string("settings.behavior.section", defaultValue: "Behavior"),
                            systemImage: "gearshape"
                        )
                        .tag(SettingsDestination.behavior)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button {
                        manager.addProfile()
                        destination = .profile(manager.selectedProfileID)
                        loadSelectedProfile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(L10n.string("settings.new_profile", defaultValue: "New profile"))
                    .disabled(manager.isEnabled)

                    Button(role: .destructive) {
                        guard case let .profile(profileID) = destination else { return }
                        manager.deleteProfile(profileID)
                        destination = .profile(manager.selectedProfileID)
                        loadSelectedProfile()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help(L10n.string("delete", defaultValue: "Delete"))
                    .disabled(manager.isEnabled || manager.profiles.count <= 1 || selectedProfileID == nil)

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch destination {
            case let .profile(profileID):
                profileSettings(for: profileID)
            case .behavior:
                defaultSettings
            case nil:
                ContentUnavailableView(
                    L10n.string("settings.profiles.section", defaultValue: "Profiles"),
                    systemImage: "sidebar.left"
                )
            }
        }
        .frame(width: 780, height: 620)
        .onAppear {
            loadSelectedProfile()
            defaultExclusionsText = manager.defaultExclusionsText
        }
        .onChange(of: destination) { oldValue, newValue in
            guard case let .profile(profileID) = newValue else { return }
            guard !manager.isEnabled else {
                destination = oldValue
                return
            }
            manager.selectProfile(profileID)
            loadSelectedProfile()
        }
        .onChange(of: manager.selectedProfileID) { _, profileID in
            if case .profile = destination {
                destination = .profile(profileID)
                loadSelectedProfile()
            }
        }
    }

    private func profileSettings(for profileID: UUID) -> some View {
        Form {
            Section(L10n.string("settings.selected_profile.section", defaultValue: "Selected profile")) {
                TextField(
                    L10n.string("settings.profile.name.placeholder", defaultValue: "Profile name"),
                    text: $profileName
                )
                .disabled(manager.isEnabled)
                .onChange(of: profileName) { _, value in
                    manager.updateProfileName(value, for: profileID)
                }

                Text(L10n.string(
                    "settings.profiles.description",
                    defaultValue: "A profile lists the applications to keep open for a specific type of work. The selected profile is applied the next time the mode is enabled."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.open_apps.label", defaultValue: "Applications to keep open")) {
                ApplicationChecklist(
                    applications: manager.availableApplications,
                    isDisabled: manager.isEnabled,
                    isSelected: { manager.isProfileProtected($0, in: profileID) },
                    setSelected: {
                        manager.setProfileProtected($0, application: $1, in: profileID)
                        loadSelectedProfile()
                    }
                )

                additionalApplicationsEditor(text: $excludedApplications) { value in
                    manager.updateProfileExclusions(value, for: profileID)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var defaultSettings: some View {
        Form {
            Section(L10n.string("settings.default_apps.section", defaultValue: "Default protected applications")) {
                Text(L10n.string(
                    "settings.default_apps.description",
                    defaultValue: "Choose the applications that should stay open in every profile. The list includes applications found on this Mac."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                ApplicationChecklist(
                    applications: manager.availableApplications,
                    isDisabled: manager.isEnabled,
                    isSelected: manager.isDefaultProtected,
                    setSelected: { manager.setDefaultProtected($0, for: $1.id) }
                )

                additionalApplicationsEditor(text: $defaultExclusionsText) { value in
                    manager.updateDefaultExclusionsText(value)
                }
            }

            Section(L10n.string("settings.behavior.section", defaultValue: "Behavior")) {
                Text(L10n.string(
                    "settings.behavior.description",
                    defaultValue: "Session mode politely quits user-interface apps not included in the list and reopens them when disabled. Clean up everything closes apps without retaining a session. Unsaved documents may prevent apps from closing."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(L10n.string("settings.protected.section", defaultValue: "Always protected")) {
                Text(L10n.string(
                    "settings.protected.description",
                    defaultValue: "System processes and background agents are never terminated."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func additionalApplicationsEditor(
        text: Binding<String>,
        onChange: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(
                "settings.default_apps.additional.label",
                defaultValue: "Additional applications"
            ))
            .font(.subheadline.weight(.semibold))

            Text(L10n.string(
                "settings.default_apps.additional.description",
                defaultValue: "For applications not shown above, enter names or bundle identifiers separated by commas."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(minHeight: 65)
                .disabled(manager.isEnabled)
                .onChange(of: text.wrappedValue) { _, value in
                    onChange(value)
                }
        }
    }

    private var selectedProfileID: UUID? {
        guard case let .profile(profileID) = destination else { return nil }
        return profileID
    }

    private func loadSelectedProfile() {
        guard let profile = manager.profiles.first(where: { $0.id == manager.selectedProfileID }) else {
            return
        }
        profileName = profile.name
        excludedApplications = profile.exclusionsText
    }
}

private struct ApplicationChecklist: View {
    let applications: [ProtectedApplication]
    let isDisabled: Bool
    let isSelected: (ProtectedApplication) -> Bool
    let setSelected: (Bool, ProtectedApplication) -> Void
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                L10n.string("settings.default_apps.search", defaultValue: "Search applications"),
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredApplications) { application in
                        Toggle(isOn: Binding(
                            get: { isSelected(application) },
                            set: { setSelected($0, application) }
                        )) {
                            HStack(spacing: 9) {
                                Image(nsImage: ApplicationIconStore.shared.icon(for: application))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 22, height: 22)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(application.name)
                                    if let bundleIdentifier = application.bundleIdentifier {
                                        Text(bundleIdentifier)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(isDisabled)
                        .padding(.vertical, 3)
                    }

                    if filteredApplications.isEmpty {
                        Text(L10n.string(
                            "settings.default_apps.empty",
                            defaultValue: "No applications match your search."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 260)
        }
    }

    private var filteredApplications: [ProtectedApplication] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let configurableApplications = applications.filter { !$0.isSystemApplication }
        guard !query.isEmpty else { return configurableApplications }
        return configurableApplications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
        }
    }
}

@MainActor
private final class ApplicationIconStore {
    static let shared = ApplicationIconStore()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for application: ProtectedApplication) -> NSImage {
        let key = application.id as NSString
        if let cachedIcon = cache.object(forKey: key) {
            return cachedIcon
        }

        let icon = application.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage()
        cache.setObject(icon, forKey: key)
        return icon
    }
}
