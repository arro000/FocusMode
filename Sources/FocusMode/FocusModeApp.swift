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
                SettingsLink {
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

struct SettingsView: View {
    @ObservedObject var manager: PerformanceManager
    @State private var profileName = ""
    @State private var excludedApplications = ""

    var body: some View {
        Form {
            Section(L10n.string("settings.profiles.section", defaultValue: "Profiles")) {
                Text(L10n.string(
                    "settings.profiles.description",
                    defaultValue: "A profile lists the applications to keep open for a specific type of work. The selected profile is applied the next time the mode is enabled."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L10n.string("profile.label", defaultValue: "Profile"), selection: Binding(
                    get: { manager.selectedProfileID },
                    set: { manager.selectProfile($0) }
                )) {
                    ForEach(manager.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .disabled(manager.isEnabled)

                HStack {
                    Button(L10n.string("settings.new_profile", defaultValue: "New profile")) {
                        manager.addProfile()
                        loadSelectedProfile()
                    }
                    .disabled(manager.isEnabled)

                    Spacer()

                    Button(L10n.string("delete", defaultValue: "Delete"), role: .destructive) {
                        manager.deleteProfile(manager.selectedProfileID)
                        loadSelectedProfile()
                    }
                    .disabled(manager.isEnabled || manager.profiles.count <= 1)
                }
            }

            Section(L10n.string("settings.selected_profile.section", defaultValue: "Selected profile")) {
                TextField(
                    L10n.string("settings.profile.name.placeholder", defaultValue: "Profile name"),
                    text: $profileName
                )
                    .disabled(manager.isEnabled)
                    .onChange(of: profileName) { _, value in
                        manager.updateProfileName(value, for: manager.selectedProfileID)
                    }

                Text(L10n.string("settings.open_apps.label", defaultValue: "Applications to keep open"))
                    .font(.subheadline.weight(.semibold))

                Text(L10n.string(
                    "settings.open_apps.description",
                    defaultValue: "Enter app names or bundle identifiers separated by commas. Matching is case-insensitive."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $excludedApplications)
                    .font(.body.monospaced())
                    .frame(minHeight: 100)
                    .disabled(manager.isEnabled)
                    .onChange(of: excludedApplications) { _, value in
                        manager.updateProfileExclusions(value, for: manager.selectedProfileID)
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
                    defaultValue: "System processes, background agents, ESET, and FortiClient are never terminated."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 350)
        .onAppear {
            loadSelectedProfile()
        }
        .onChange(of: manager.selectedProfileID) { _, _ in
            loadSelectedProfile()
        }
    }

    private func loadSelectedProfile() {
        guard let profile = manager.profiles.first(where: { $0.id == manager.selectedProfileID }) else {
            return
        }

        profileName = profile.name
        excludedApplications = profile.exclusionsText
    }
}
