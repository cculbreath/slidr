import SwiftUI

struct AISettingsView: View {
    @Bindable var settings: AppSettings

    @State private var xaiKeyInput = ""
    @State private var groqKeyInput = ""
    @State private var hasXAIKey = false
    @State private var hasGroqKey = false
    @State private var xaiTestStatus: KeyTestStatus = .idle
    @State private var groqTestStatus: KeyTestStatus = .idle
    @State private var xaiModels: [String] = []
    @State private var groqModels: [String] = []

    var body: some View {
        Form {
            apiKeysSection
            modelsSection
            processingSection
        }
        .formStyle(.grouped)
        .onAppear {
            hasXAIKey = KeychainService.exists(key: KeychainService.xaiAPIKeyName)
            hasGroqKey = KeychainService.exists(key: KeychainService.groqAPIKeyName)
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        Section("API Keys") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("xAI API Key", text: $xaiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    if hasXAIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Button("Save") {
                        saveXAIKey()
                    }
                    .disabled(xaiKeyInput.isEmpty)

                    if hasXAIKey {
                        Button("Test") {
                            testXAIKey()
                        }
                        .disabled(xaiTestStatus == .testing)

                        Button("Clear") {
                            KeychainService.delete(key: KeychainService.xaiAPIKeyName)
                            hasXAIKey = false
                            xaiTestStatus = .idle
                            xaiModels = []
                        }
                    }
                }

                keyTestStatusView(status: xaiTestStatus)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Groq API Key", text: $groqKeyInput)
                        .textFieldStyle(.roundedBorder)

                    if hasGroqKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Button("Save") {
                        saveGroqKey()
                    }
                    .disabled(groqKeyInput.isEmpty)

                    if hasGroqKey {
                        Button("Test") {
                            testGroqKey()
                        }
                        .disabled(groqTestStatus == .testing)

                        Button("Clear") {
                            KeychainService.delete(key: KeychainService.groqAPIKeyName)
                            hasGroqKey = false
                            groqTestStatus = .idle
                            groqModels = []
                        }
                    }
                }

                keyTestStatusView(status: groqTestStatus)
            }
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        Section("Models") {
            if xaiModels.isEmpty {
                TextField("xAI Model", text: Binding(
                    get: { settings.aiModel },
                    set: { settings.aiModel = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                Picker("xAI Model", selection: Binding(
                    get: { settings.aiModel },
                    set: { settings.aiModel = $0 }
                )) {
                    ForEach(xaiModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            if groqModels.isEmpty {
                TextField("Groq Whisper Model", text: Binding(
                    get: { settings.groqModel },
                    set: { settings.groqModel = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            } else {
                Picker("Groq Whisper Model", selection: Binding(
                    get: { settings.groqModel },
                    set: { settings.groqModel = $0 }
                )) {
                    ForEach(groqModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        }
    }

    // MARK: - Processing

    private var processingSection: some View {
        Section("Processing") {
            Toggle("Auto-process on import", isOn: Binding(
                get: { settings.aiAutoProcessOnImport },
                set: { settings.aiAutoProcessOnImport = $0 }
            ))

            Toggle("Auto-transcribe on import", isOn: Binding(
                get: { settings.aiAutoTranscribeOnImport },
                set: { settings.aiAutoTranscribeOnImport = $0 }
            ))

            Picker("Tag Mode", selection: Binding(
                get: { settings.aiTagMode },
                set: { settings.aiTagMode = $0 }
            )) {
                ForEach(AITagMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }

    // MARK: - Key Test Status

    @ViewBuilder
    private func keyTestStatusView(status: KeyTestStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                SpinnerView()
                Text("Testing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .success(let message):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        case .failure(let message):
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Save Keys

    private func saveXAIKey() {
        let trimmed = xaiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainService.save(key: KeychainService.xaiAPIKeyName, value: trimmed)
        } catch {
            xaiTestStatus = .failure("Keychain save failed: \(error.localizedDescription)")
            return
        }

        guard let readBack = KeychainService.load(key: KeychainService.xaiAPIKeyName) else {
            xaiTestStatus = .failure("Key saved but could not be read back from keychain")
            return
        }

        if readBack != trimmed {
            xaiTestStatus = .failure("Keychain roundtrip mismatch: saved \(trimmed.count) chars, read \(readBack.count) chars")
            return
        }

        xaiKeyInput = ""
        hasXAIKey = true
        testXAIKey()
    }

    private func saveGroqKey() {
        let trimmed = groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainService.save(key: KeychainService.groqAPIKeyName, value: trimmed)
        } catch {
            groqTestStatus = .failure("Keychain save failed: \(error.localizedDescription)")
            return
        }

        guard let readBack = KeychainService.load(key: KeychainService.groqAPIKeyName) else {
            groqTestStatus = .failure("Key saved but could not be read back from keychain")
            return
        }

        if readBack != trimmed {
            groqTestStatus = .failure("Keychain roundtrip mismatch: saved \(trimmed.count) chars, read \(readBack.count) chars")
            return
        }

        groqKeyInput = ""
        hasGroqKey = true
        testGroqKey()
    }

    // MARK: - API Testing

    private func testXAIKey() {
        guard let apiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else {
            xaiTestStatus = .failure("No key found in keychain")
            return
        }

        let keyInfo = "(\(apiKey.count) chars, prefix: \(String(apiKey.prefix(8)))...)"
        xaiTestStatus = .testing

        Task {
            do {
                let models = try await fetchModels(
                    endpoint: URL(string: "https://api.x.ai/v1/models")!,
                    apiKey: apiKey
                )
                xaiModels = models.sorted()
                xaiTestStatus = .success("Connected - \(models.count) models available")
            } catch let error as KeyTestError {
                xaiTestStatus = .failure("\(error.message) \(keyInfo)")
            } catch {
                xaiTestStatus = .failure("\(error.localizedDescription) \(keyInfo)")
            }
        }
    }

    private func testGroqKey() {
        guard let apiKey = KeychainService.load(key: KeychainService.groqAPIKeyName) else {
            groqTestStatus = .failure("No key found in keychain")
            return
        }

        let keyInfo = "(\(apiKey.count) chars, prefix: \(String(apiKey.prefix(8)))...)"
        groqTestStatus = .testing

        Task {
            do {
                let models = try await fetchModels(
                    endpoint: URL(string: "https://api.groq.com/openai/v1/models")!,
                    apiKey: apiKey
                )
                let whisperModels = models.filter { $0.contains("whisper") }
                groqModels = whisperModels.isEmpty ? models.sorted() : whisperModels.sorted()
                groqTestStatus = .success("Connected - \(models.count) models (\(whisperModels.count) whisper)")
            } catch let error as KeyTestError {
                groqTestStatus = .failure("\(error.message) \(keyInfo)")
            } catch {
                groqTestStatus = .failure("\(error.localizedDescription) \(keyInfo)")
            }
        }
    }

    private func fetchModels(endpoint: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KeyTestError(message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw KeyTestError(message: "HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsArray = json["data"] as? [[String: Any]] else {
            throw KeyTestError(message: "Unexpected response format")
        }

        return modelsArray.compactMap { $0["id"] as? String }
    }
}

// MARK: - Supporting Types

private enum KeyTestStatus: Equatable {
    case idle
    case testing
    case success(String)
    case failure(String)
}

private struct KeyTestError: Error {
    let message: String
}
