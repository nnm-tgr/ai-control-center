import SwiftUI
import UniformTypeIdentifiers

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

            TaskCategorySettingsView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
                .tag(4)
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

            Section("Tool Approval") {
                Toggle("Require approval before tool execution", isOn: $appState.settings.approvalEnabled)
                if appState.settings.approvalEnabled {
                    Stepper(
                        "Timeout: \(appState.settings.approvalTimeoutSeconds)s (auto-allow)",
                        value: $appState.settings.approvalTimeoutSeconds,
                        in: 10...120,
                        step: 5
                    )
                }
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
    @State private var isImporting = false

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
                    let urls = offsets.map { appState.settings.watchedRootURLs[$0] }
                    urls.forEach { appState.removeWatchedRoot($0) }
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
                Button { isImporting = true } label: {
                    Label("Add", systemImage: "plus")
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        Task { @MainActor in
                            appState.addWatchedRoot(url)
                        }
                    }
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

    private func removeSelected() {
        guard let url = selectedURL else { return }
        appState.removeWatchedRoot(url)
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

// MARK: - Task Categories

private struct TaskCategorySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var editingID: UUID? = nil
    @State private var editingName: String = ""
    @State private var isAdding: Bool = false
    @State private var newName: String = ""
    @State private var newColorHex: String = TaskCategory.presetColors[0]

    private var taskStore: TaskStore { appState.taskStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Categories")
                .font(.headline)

            List {
                ForEach(taskStore.categories) { category in
                    categoryRow(category)
                }
                .onDelete { offsets in
                    offsets.map { taskStore.categories[$0].id }
                        .forEach { taskStore.deleteCategory(id: $0) }
                }

                if isAdding {
                    addRow
                }
            }
            .frame(minHeight: 180)
            .overlay {
                if taskStore.categories.isEmpty && !isAdding {
                    ContentUnavailableView(
                        "No categories",
                        systemImage: "tag",
                        description: Text("Click + to add a category.")
                    )
                }
            }

            HStack {
                Button {
                    isAdding = true
                    newName = ""
                    newColorHex = TaskCategory.presetColors[0]
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(isAdding)

                Button {
                    guard let id = editingID ?? taskStore.categories.first?.id else { return }
                    taskStore.deleteCategory(id: id)
                    editingID = nil
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(taskStore.categories.isEmpty)

                Spacer()
            }
            .buttonStyle(.bordered)

            Text("Categories are labels you can assign to any task to group them semantically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func categoryRow(_ category: TaskCategory) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: category.colorHex))
                .frame(width: 10, height: 10)

            if editingID == category.id {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitEdit(category) }
                Button("Done") { commitEdit(category) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Text(category.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture {
                        editingID = category.id
                        editingName = category.name
                    }
            }
        }
        .tag(category.id)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            colorSwatches(selection: $newColorHex)

            TextField("Category name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitAdd() }

            Button("Add") { commitAdd() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel") { isAdding = false }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func colorSwatches(selection: Binding<String>) -> some View {
        HStack(spacing: 4) {
            ForEach(TaskCategory.presetColors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .opacity(selection.wrappedValue == hex ? 1 : 0)
                    )
                    .onTapGesture { selection.wrappedValue = hex }
            }
        }
    }

    private func commitAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        taskStore.addCategory(TaskCategory(name: name, colorHex: newColorHex))
        isAdding = false
    }

    private func commitEdit(_ original: TaskCategory) {
        let name = editingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { editingID = nil; return }
        var updated = original
        updated.name = name
        taskStore.updateCategory(updated)
        editingID = nil
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
