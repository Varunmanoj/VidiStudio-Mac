import SwiftUI

private struct GeminiModelRow: Identifiable {
    let id: String
    let label: String
}

private enum GeminiModelGroup: Int, CaseIterable, Identifiable {
    case latest
    case flash
    case flashLite
    case pro
    case gemini4
    case omni
    case speech
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .flash: "Flash"
        case .flashLite: "Flash-Lite"
        case .pro: "Pro"
        case .gemini4: "Gemini 4"
        case .omni: "Omni"
        case .speech: "Speech and transcription"
        case .other: "Other models"
        }
    }
}

private struct GeminiModelMenuGroup: Identifiable {
    let group: GeminiModelGroup
    let options: [GeminiModelOption]

    var id: GeminiModelGroup { group }
}

struct VertexModelPolicy: Decodable {
    struct Group: Decodable {
        let title: String
        let capability: String
        let pattern: String
    }
    struct ProjectModelRow: Decodable, Identifiable {
        let id: String
        let stage: String
        let label: String
        let fallback: String?
        let signInOnly: Bool?
    }
    struct ProjectGroup: Decodable, Identifiable {
        var id: String { title }
        let title: String
        let signInOnly: Bool
        let rows: [ProjectModelRow]
    }
    let projectModelGroups: [ProjectGroup]
    let groups: [Group]
    let stages: [String: String]
    let preferred: [String: [String]]
    let expressModels: [String]

    static let bundled: VertexModelPolicy? = {
        struct Defaults: Decodable { let vertexModelPolicy: VertexModelPolicy }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Defaults.self, from: data))?.vertexModelPolicy
    }()
}

private enum GeminiOutputLanguages {
    static let options: [GeminiModelRow] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/_internal/ai-defaults.json"),
              let data = try? Data(contentsOf: url),
              let defaults = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let languages = defaults["outputLanguageOptions"] as? [String: String] else { return [] }
        return languages.map { GeminiModelRow(id: $0.key, label: $0.value) }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }()
}

struct GeminiAPISettingsView: View {
    @Bindable var studio: StudioModel
    @Environment(\.openURL) private var openURL
    @State private var removingGoogleSignIn = false
    @State private var vertexKey = ""
    @State private var vertexStatus = ""
    @State private var keyDebounceTask: Task<Void, Never>?
    @State private var showingDeleteConfirmation = false
    @State private var advancedExpanded = false
    @State private var apiKey: String

    init(studio: StudioModel) {
        self.studio = studio
        _apiKey = State(initialValue: studio.settings.apiKey)
    }

    private var hasApiKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var keyStatusLabel: String {
        guard hasApiKey else { return "No API Key Entered" }
        if studio.busy { return "Checking API key…" }
        if let failure = studio.apiKeyCheckFailureMessage { return "API Key Check Incomplete. " + failure }
        if studio.apiKeyVerified == true { return "API Key Verified. " + (studio.apiKeyVerificationMessage ?? "") }
        if studio.apiKeyVerified == false { return "Invalid API Key. " + (studio.apiKeyVerificationMessage ?? "Google rejected this key.") }
        return "API Key Not Checked"
    }
    private var keyStatusSymbol: String {
        guard hasApiKey else { return "key" }
        if studio.busy { return "clock" }
        if studio.apiKeyCheckFailureMessage != nil { return "exclamationmark.triangle.fill" }
        if studio.apiKeyVerified == true { return "checkmark.circle.fill" }
        if studio.apiKeyVerified == false { return "xmark.circle.fill" }
        return "key"
    }
    private var keyStatusColor: Color {
        guard hasApiKey, !studio.busy, studio.apiKeyCheckFailureMessage == nil else { return .secondary }
        return studio.apiKeyVerified == true ? .green : studio.apiKeyVerified == false ? .red : .secondary
    }

    private let apiKeyPage = URL(string: "https://aistudio.google.com/api-keys")!

    private func choiceMenu(_ selection: Binding<String>, options: [(String, String)]) -> some View {
        ForEach(options, id: \.0) { option in
            Toggle(option.1, systemImage: "cpu", isOn: Binding(get: { selection.wrappedValue == option.0 }, set: { if $0 { selection.wrappedValue = option.0 } }))
        }
    }

    var body: some View {
        Section("AI provider") {
            Picker("Provider", selection: $studio.settings.aiProvider) {
                Text("Gemini Developer API").tag("developer")
                Text("Vertex AI").tag("vertex")
            }.contextMenu { choiceMenu($studio.settings.aiProvider, options: [("developer", "Gemini Developer API"), ("vertex", "Vertex AI")]) }
        }.disabled(studio.busy)
        outputLanguageSections
        if studio.settings.aiProvider == "vertex" { vertexSettings } else { developerSettings }
    }

    private func clearVertexTestResult() {
        studio.vertexConnectionVerified = false
        studio.vertexConnectionMessage = ""
    }

    private func storeVertexKey(_ value: String) {
        if KeychainStore.vertex.write(value) {
            studio.settings.vertexCredentialRevision += 1
            vertexKey = ""
            vertexStatus = value.isEmpty ? "Key removed" : "Key saved"
        } else { vertexStatus = "Could not update Keychain" }
    }

    private func cloudField(_ label: String, _ value: Binding<String>) -> some View {
        let copy = {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value.wrappedValue, forType: .string)
        }
        let clear = { value.wrappedValue = "" }
        return LabeledContent(label) {
            HStack {
                TextField(label, text: value).labelsHidden()
                Button("Copy " + label, systemImage: "doc.on.doc", action: copy)
                    .labelStyle(.iconOnly).help("Copy " + label).disabled(value.wrappedValue.isEmpty)
                Button("Clear " + label, systemImage: "trash", role: .destructive, action: clear)
                    .labelStyle(.iconOnly).help("Clear " + label).disabled(value.wrappedValue.isEmpty)
            }
            .contextMenu {
                Button("Copy " + label, systemImage: "doc.on.doc", action: copy).disabled(value.wrappedValue.isEmpty)
                Button("Clear " + label, systemImage: "trash", role: .destructive, action: clear).disabled(value.wrappedValue.isEmpty)
            }
        }
    }

    @ViewBuilder private var expressKeyActions: some View {
        Button("Save Key") { storeVertexKey(vertexKey) }.disabled(vertexKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Remove Key") { storeVertexKey("") }.disabled(!KeychainStore.vertex.containsValue())
        Button("Use Google sign-in") { studio.settings.vertexAuth = "signin" }
    }

    private func updateGoogleSignIn(disconnect: Bool) {
        Task {
            do {
                if disconnect { try await YouTubeService.shared.disconnectCloudAccount() }
                else { try await YouTubeService.shared.signInToCloud() }
                studio.settings.vertexConnected = KeychainStore.hasVertexSignIn
                studio.invalidateCloudPermissions()
            } catch is CancellationError {
            } catch { studio.error = error.localizedDescription }
        }
    }

    @ViewBuilder private var googleSignInActions: some View {
        Button(studio.settings.vertexConnected ? "Reconnect Google Account" : "Sign in with Google") { updateGoogleSignIn(disconnect: false) }
            .disabled(YouTubeService.shared.signingIn)
        Button("Remove Google sign-in", systemImage: "trash", role: .destructive) { removingGoogleSignIn = true }
            .disabled(!studio.settings.vertexConnected || YouTubeService.shared.signingIn)
    }

    @ViewBuilder private var vertexSettings: some View {
        Section("Vertex AI") {
            Picker("Authentication", selection: $studio.settings.vertexAuth) {
                Text("Google sign-in").tag("signin")
                Text("Express API key").tag("express")
            }.contextMenu { choiceMenu($studio.settings.vertexAuth, options: [("signin", "Google sign-in"), ("express", "Express API key")]) }
            if studio.settings.vertexAuth == "express" {
                SecureField("Vertex AI express API key", text: $vertexKey)
                HStack { expressKeyActions }.contextMenu { expressKeyActions }
                if KeychainStore.vertex.containsValue() { Text("Express key saved") }
            } else {
                cloudField("Google Cloud project ID", $studio.settings.vertexProject)
                cloudField("Cloud Storage bucket", $studio.settings.vertexBucket)
                let connected = studio.settings.vertexConnected
                Label(connected ? "Google account connected" : "Signed out",
                      systemImage: connected ? "checkmark.circle.fill" : "person.crop.circle")
                    .foregroundStyle(connected ? Color.green : Color.secondary)
                    .accessibilityIdentifier("vertex-signin-status")
                    .onAppear { studio.settings.vertexConnected = KeychainStore.hasVertexSignIn }
                    .onChange(of: connected) { _, active in
                        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                            userInfo: [.announcement: active ? "Google account connected" : "Signed out", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                    }
                HStack { googleSignInActions }
                    .contextMenu { googleSignInActions }
                    .alert("Remove Google sign-in from this Mac?", isPresented: $removingGoogleSignIn) {
                        Button("Remove Google sign-in", role: .destructive) { updateGoogleSignIn(disconnect: true) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This removes Google Cloud access from this Mac. Your YouTube accounts and projects stay available.")
                    }
            }
            HStack(spacing: 8) {
                Button("Test Connection") { studio.execute("vertex-check") }
                    .contextMenu { Button("Test Connection") { studio.execute("vertex-check") } }
                if studio.vertexConnectionVerified {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Vertex AI connection verified")
                        .accessibilityIdentifier("vertex-test-status")
                        .help("Vertex AI connection verified")
                }
            }
            .onChange(of: studio.vertexConnectionVerified) { _, verified in
                if verified {
                    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                        userInfo: [.announcement: "Vertex AI connection verified", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                }
            }
            if !vertexStatus.isEmpty { Text(vertexStatus) }
            if !studio.vertexConnectionMessage.isEmpty { Text(studio.vertexConnectionMessage) }
        }.disabled(studio.busy)
        .onChange(of: studio.settings.vertexAuth) { clearVertexTestResult() }
        .onChange(of: studio.settings.vertexProject) { clearVertexTestResult() }
        .onChange(of: studio.settings.vertexBucket) { clearVertexTestResult() }
        .onChange(of: studio.settings.vertexCredentialRevision) { clearVertexTestResult() }
        let express = studio.settings.vertexAuth == "express"
        let groups = VertexModelPolicy.bundled?.projectModelGroups ?? []
        ForEach(groups.filter { !express || !$0.signInOnly }) { group in
            Section(group.title) {
                ForEach(group.rows.filter { !express || $0.signInOnly != true }) { row in
                    vertexModelPicker(row, express: express)
                }
            }
        }
    }

    private func vertexModelPicker(_ row: VertexModelPolicy.ProjectModelRow, express: Bool) -> some View {
        let policy = VertexModelPolicy.bundled
        let capability = policy?.stages[row.stage] ?? ""
        let catalog = express ? policy?.expressModels ?? [] : studio.settings.vertexCatalog
        let groups = (policy?.groups ?? []).compactMap { group -> (title: String, names: [String])? in
            guard group.capability == capability else { return nil }
            let names = Set(catalog.filter { $0.range(of: group.pattern, options: .regularExpression) != nil }).sorted()
            return names.isEmpty ? nil : (group.title, names)
        }
        let choices = groups.flatMap(\.names)
        func selectedModel(_ saved: [String: String]) -> String {
            [saved[row.id], saved[row.fallback ?? row.stage]].compactMap { $0 }.first(where: choices.contains)
                ?? policy?.preferred[capability]?.first(where: choices.contains) ?? choices.sorted().first ?? ""
        }
        let selection = Binding<String>(get: {
            selectedModel(express ? studio.settings.vertexExpressModels : studio.settings.vertexModels)
        }, set: { value in
            guard choices.contains(value) else { return }
            var saved = express ? studio.settings.vertexExpressModels : studio.settings.vertexModels
            let previous = selectedModel(saved)
            // Keep inherited choices stable when their previous default is edited.
            for dependent in policy?.projectModelGroups.flatMap(\.rows) ?? []
                where dependent.id != row.id && (dependent.fallback ?? dependent.stage) == row.id && saved[dependent.id] == nil {
                saved[dependent.id] = previous
            }
            saved[row.id] = value
            if express { studio.settings.vertexExpressModels = saved }
            else { studio.settings.vertexModels = saved }
        })
        let emptyLabel = express ? "Unavailable in express mode" : "No compatible models"
        return Picker(row.label, selection: selection) {
            if choices.isEmpty { Text(emptyLabel).tag("") }
            ForEach(groups, id: \.title) { group in
                modelOptionsSection(group.title, options: group.names.map(GeminiModelOption.init(name:)), exactIDs: true)
            }
        }
        .accessibilityIdentifier("vertex-model-" + row.id)
        .contextMenu {
            ForEach(groups, id: \.title) { group in
                Section(group.title) { choiceMenu(selection, options: group.names.map { ($0, $0) }) }
            }
        }
        .disabled(choices.isEmpty)
    }

    @ViewBuilder private var developerSettings: some View {
        Section {
            HStack(spacing: 8) {
                SecureField("API key", text: $apiKey)
                    .accessibilityIdentifier("gemini-api-key")
                    .accessibilityHint("Enter the key from your Google AI Studio account.")
                    .onSubmit {
                        keyDebounceTask?.cancel()
                        studio.checkGeminiApiKey()
                    }
                    .onAppear { apiKey = studio.settings.apiKey }
                    .onChange(of: apiKey) { _, newValue in
                        studio.settings.apiKey = newValue
                        keyDebounceTask?.cancel()
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else {
                            studio.apiKeyVerified = nil
                            studio.apiKeyVerificationMessage = nil
                            return
                        }
                        keyDebounceTask = Task {
                            try? await Task.sleep(nanoseconds: 700_000_000)
                            if !Task.isCancelled && ConnectivityService.shared.available(.gemini) {
                                studio.checkGeminiApiKey()
                            }
                        }
                    }

                Image(systemName: keyStatusSymbol)
                    .foregroundStyle(keyStatusColor)
                    .help(keyStatusLabel).accessibilityLabel(keyStatusLabel)
                    .accessibilityIdentifier("gemini-key-status")

                if hasApiKey {
                    Button(role: .destructive) {
                        guard hasApiKey, !studio.busy else { return }
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(studio.busy)
                    .help("Delete API key from Keychain")
                    .accessibilityLabel("Delete Gemini API key")
                    .accessibilityIdentifier("gemini-key-delete-icon")
                }
            }
            .alert("Delete Gemini API Key?", isPresented: $showingDeleteConfirmation) {
                Button("Delete API Key", role: .destructive) {
                    guard hasApiKey, !studio.busy else { return }
                    keyDebounceTask?.cancel()
                    studio.deleteGeminiApiKey()
                    apiKey = ""
                }
                // Removing a local credential must remain available offline.
                .disabled(!hasApiKey || studio.busy)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete your Gemini API key from macOS Keychain? You will need to enter a new key to use AI features.")
            }
            HStack(spacing: 8) {
                Button(studio.geminiModelsLoaded ? "Check API Key & Reload Models" : "Check API Key & Plan", systemImage: "arrow.clockwise") {
                    keyDebounceTask?.cancel()
                    studio.checkGeminiApiKey()
                }
                .disabled(studio.busy)
                .accessibilityHint("Checks the validity of your Gemini API key and detects available models and plan tier.")
                .requiresInternet(hasApiKey ? .gemini : nil)
                Button("Open API Keys in Google AI Studio", systemImage: "arrow.up.right.square") {
                    openURL(apiKeyPage)
                }
                .accessibilityHint("Opens the Google AI Studio API Keys page in your web browser.")

            }

            if hasApiKey, let failure = studio.apiKeyCheckFailureMessage {
                Text(failure).font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Connect to Gemini").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
        .onChange(of: studio.apiKeyVerificationMessage) { _, result in
            if let result {
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [.announcement: result, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
        .onChange(of: studio.apiKeyCheckFailureMessage) { _, result in
            if let result {
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [.announcement: "API Key Check Incomplete. " + result, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
        }
        .onAppear {
            if hasApiKey && studio.apiKeyVerified == nil && !studio.busy && ConnectivityService.shared.available(.gemini) {
                studio.checkGeminiApiKey()
            }
        }

        if hasApiKey {
            Section {
                HStack {
                    Text("Plan Tier")
                        .fontWeight(.medium)
                    Spacer()
                    if studio.busy {
                        ProgressView().controlSize(.small)
                    } else if studio.apiKeyVerified == false {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Invalid Key")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12), in: Capsule())
                    } else if studio.apiKeyVerified == nil {
                        Text("Not Checked").foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(studio.settings.geminiPlan == "paid" ? Color.blue : Color.secondary)
                                .frame(width: 8, height: 8)
                            Text(studio.settings.geminiPlan == "paid" ? "Paid Plan" : "Free Plan")
                                .fontWeight(.semibold)
                                .foregroundStyle(studio.settings.geminiPlan == "paid" ? Color.blue : Color.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(studio.settings.geminiPlan == "paid" ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Account Plan: \(studio.apiKeyVerified == nil ? "Not Checked" : (studio.apiKeyVerified == false ? "Invalid Key" : (studio.settings.geminiPlan == "paid" ? "Paid Plan" : "Free Plan")))")

                if studio.apiKeyVerified == false {
                    Text("The plan tier cannot be determined because the API key is invalid.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if studio.apiKeyVerified == nil {
                    Text("Check the entered API key before showing account information.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(studio.settings.geminiPlan == "paid"
                        ? "Paid plan: higher limits and enterprise data privacy."
                        : "Free plan: standard limits and quota.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: { Text("Account Plan").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
        }

        ForEach((VertexModelPolicy.bundled?.projectModelGroups ?? []).filter { !$0.signInOnly }) { group in
            Section {
                ForEach(group.rows) { row in
                    modelPicker(row)
                }
            } header: {
                Text(group.title).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2)
            }
        }
        Section {
            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                Picker("Video processing", selection: $studio.settings.videoProcessing) {
                    Text("Agentic").tag("agentic")
                    Text("Static").tag("static")
                }
                .pickerStyle(.menu)
                .accessibilityHint("Choose Static for fixed video sampling or Agentic for model-directed video analysis.")
            }
        }
    }

    @ViewBuilder
    private var outputLanguageSections: some View {
        Section {
            OutputLanguagePicker(title: "Default Language for New Projects", selection: Binding(get: {
                if let value = studio.settings.defaultOutputLanguage { return value }
                let values = Set(["transcript", "summary", "audio_descriptions"].map { studio.settings.outputLanguages[$0] ?? "auto" })
                return values.count == 1 ? values.first! : "auto"
            }, set: { studio.settings.defaultOutputLanguage = $0 }))
        } header: { Text("Language").accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
    }

    private func modelBinding(_ stage: String) -> Binding<String> {
        Binding(
            get: { studio.settings.models[stage] ?? "" },
            set: { studio.settings.models[stage] = $0 }
        )
    }

    private func modelPicker(_ row: VertexModelPolicy.ProjectModelRow) -> some View {
        let selection = modelBinding(row.id)
        let groups = modelGroups(for: row.stage)
        return Picker(row.label, selection: selection) {
            ForEach(groups) { modelGroup in
                modelOptionsSection(modelGroup.group.title, options: modelGroup.options)
            }
        }
        .contextMenu {
            ForEach(groups) { group in
                Section(group.group.title) {
                    choiceMenu(selection, options: group.options.map { ($0.name, modelDisplayName($0.name)) })
                }
            }
        }
        .disabled(!studio.geminiModelsLoaded)
        .accessibilityHint("Choose from models available to your Gemini account.")
    }

    private func modelOptionsSection(_ title: String, options: [GeminiModelOption], exactIDs: Bool = false) -> some View {
        Section {
            ForEach(options) { option in
                Text(exactIDs ? option.name : modelDisplayName(option.name)).tag(option.name)
            }
        } header: { Text(title).accessibilityAddTraits(.isHeader).accessibilityHeading(.h2) }
    }

    private func modelGroups(for stage: String) -> [GeminiModelMenuGroup] {
        let grouped = Dictionary(grouping: studio.geminiModels(for: stage)) { option in
            modelGroup(for: option.name)
        }

        return GeminiModelGroup.allCases.compactMap { group in
            guard let options = grouped[group], !options.isEmpty else { return nil }
            return GeminiModelMenuGroup(
                group: group,
                options: options.sorted {
                    modelDisplayName($0.name).localizedStandardCompare(modelDisplayName($1.name)) == .orderedAscending
                }
            )
        }
    }

    private func modelGroup(for name: String) -> GeminiModelGroup {
        let normalized = name.lowercased()
        if normalized.range(of: #"^(?:models/)?gemini-4(?:[.-]|$)"#, options: .regularExpression) != nil { return .gemini4 }
        if normalized.contains("latest") { return .latest }
        if normalized.contains("tts") || normalized.contains("transcribe") { return .speech }
        if normalized.contains("flash-lite") { return .flashLite }
        if normalized.contains("pro") { return .pro }
        if normalized.contains("omni") { return .omni }
        if normalized.contains("flash") { return .flash }
        return .other
    }

    private func modelDisplayName(_ name: String) -> String {
        var tokens = name
            .replacingOccurrences(of: "models/", with: "")
            .split(separator: "-")
            .map(String.init)

        if tokens.first?.lowercased() == "gemini" {
            tokens.removeFirst()
        }

        var qualifiers: [String] = []
        if removeToken("latest", from: &tokens) { qualifiers.append("Latest") }
        if removeToken("preview", from: &tokens) { qualifiers.append("Preview") }
        if removeToken("experimental", from: &tokens) || removeToken("exp", from: &tokens) {
            qualifiers.append("Experimental")
        }
        if removeSequence(["custom", "tools"], from: &tokens) {
            qualifiers.append("Custom Tools")
        }

        var components: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index].lowercased()
            if token == "flash", index + 1 < tokens.count, tokens[index + 1].lowercased() == "lite" {
                components.append("Flash-Lite")
                index += 2
                continue
            }
            components.append(formattedModelToken(tokens[index]))
            index += 1
        }

        let modelName = (["Gemini"] + components).joined(separator: " ")
        guard !qualifiers.isEmpty else { return modelName }
        return "\(modelName) — \(qualifiers.joined(separator: ", "))"
    }

    private func formattedModelToken(_ token: String) -> String {
        switch token.lowercased() {
        case "tts": "TTS"
        case "pro": "Pro"
        case "flash": "Flash"
        case "lite": "Lite"
        case "omni": "Omni"
        case "transcribe": "Transcribe"
        case "image": "Image"
        case "live": "Live"
        default: token.first?.isNumber == true ? token : token.capitalized
        }
    }

    private func removeToken(_ token: String, from tokens: inout [String]) -> Bool {
        guard let index = tokens.firstIndex(where: { $0.caseInsensitiveCompare(token) == .orderedSame }) else {
            return false
        }
        tokens.remove(at: index)
        return true
    }

    private func removeSequence(_ sequence: [String], from tokens: inout [String]) -> Bool {
        guard sequence.count <= tokens.count else { return false }
        for start in 0...(tokens.count - sequence.count) {
            let candidate = tokens[start..<(start + sequence.count)].map { $0.lowercased() }
            if candidate == sequence {
                tokens.removeSubrange(start..<(start + sequence.count))
                return true
            }
        }
        return false
    }
}
