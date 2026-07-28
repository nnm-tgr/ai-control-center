import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            DirectoriesSettingsView()
                .tabItem { Label("Directories", systemImage: "folder") }
                .tag(1)

            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(2)

            TerminalSettingsView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
                .tag(3)
        }
        .frame(width: 520)
        .fixedSize()
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Appearance") {
                Toggle("Show menu bar icon", isOn: $appState.settings.showMenuBarIcon)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $appState.settings.launchAtLogin)
            }

            Section("Scan") {
                Stepper(
                    "Scan depth: \(appState.settings.scanDepth) levels",
                    value: $appState.settings.scanDepth,
                    in: 1...6
                )
            }

            Section("Activity") {
                Stepper(
                    "Keep last \(appState.settings.activityRetentionCount) events",
                    value: $appState.settings.activityRetentionCount,
                    in: 50...500,
                    step: 50
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Directories

private struct DirectoriesSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedURL: URL?

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 12) {
            Text("Watched Root Directories")
                .font(.headline)

            List(selection: $selectedURL) {
                ForEach(appState.settings.watchedRootURLs, id: \.self) { url in
                    Text(url.path)
                        .font(.body)
                        .tag(url)
                }
                .onDelete { offsets in
                    appState.updateSettings { $0.watchedRootURLs.remove(atOffsets: offsets) }
                }
            }
            .frame(minHeight: 160)
            .overlay {
                if appState.settings.watchedRootURLs.isEmpty {
                    ContentUnavailableView(
                        "No directories",
                        systemImage: "folder.badge.plus",
                        description: Text("Click + to add a root directory to watch.")
                    )
                }
            }

            HStack {
                Button(action: addDirectory) {
                    Label("Add", systemImage: "plus")
                }
                Button(action: removeSelected) {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selectedURL == nil)

                Spacer()

                Button("Rescan Now") {
                    Task { await appState.refresh() }
                }
                .disabled(appState.isScanning)
            }
            .buttonStyle(.bordered)

            Divider()

            Text("Excluded Directory Names")
                .font(.headline)

            TextEditor(text: Binding(
                get: { appState.settings.excludedDirectoryNames.joined(separator: "\n") },
                set: { text in
                    appState.updateSettings {
                        $0.excludedDirectoryNames = text
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(height: 100)
            .border(Color.secondary.opacity(0.3))

            Text("One name per line. These folder names are skipped during scan and file watching.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Root Directory"
        if panel.runModal() == .OK, let url = panel.url {
            appState.updateSettings { settings in
                if !settings.watchedRootURLs.contains(url) {
                    settings.watchedRootURLs.append(url)
                }
            }
        }
    }

    private func removeSelected() {
        guard let url = selectedURL else { return }
        appState.updateSettings { $0.watchedRootURLs.removeAll { $0 == url } }
        selectedURL = nil
    }
}

// MARK: - Notifications

private struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Toggle("Enable notifications", isOn: $appState.settings.notificationsEnabled)
                Toggle("Do not disturb", isOn: $appState.settings.doNotDisturbEnabled)
            }

            Section("Minimum Level") {
                Picker("Notify when level ≥", selection: $appState.settings.notificationLevel) {
                    ForEach(NotificationLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!appState.settings.notificationsEnabled)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Terminal

private struct TerminalSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Preferred Terminal") {
                Picker("Terminal app", selection: $appState.settings.preferredTerminal) {
                    ForEach(TerminalProviderType.allCases, id: \.self) { provider in
                        HStack {
                            Text(provider.rawValue.capitalized)
                            if !provider.isInstalled {
                                Text("(not installed)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Git Integration") {
                Toggle("Enable git integration", isOn: $appState.settings.gitIntegrationEnabled)
                if appState.settings.gitIntegrationEnabled {
                    Stepper(
                        "Poll every \(Int(appState.settings.gitPollInterval))s",
                        value: $appState.settings.gitPollInterval,
                        in: 10...300,
                        step: 10
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView()
        .environment(AppState())
}

#Preview("Settings — Dark") {
    SettingsView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
