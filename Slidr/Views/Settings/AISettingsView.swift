import SwiftUI

struct AISettingsView: View {
    @Bindable var settings: AppSettings

    @State private var xaiKeyInput = ""
    @State private var groqKeyInput = ""
    @State private var hasXAIKey = false
    @State private var hasGroqKey = false

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
            HStack {
                SecureField("xAI API Key", text: $xaiKeyInput)
                    .textFieldStyle(.roundedBorder)

                if hasXAIKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button("Save") {
                    guard !xaiKeyInput.isEmpty else { return }
                    try? KeychainService.save(key: KeychainService.xaiAPIKeyName, value: xaiKeyInput)
                    xaiKeyInput = ""
                    hasXAIKey = true
                }
                .disabled(xaiKeyInput.isEmpty)

                if hasXAIKey {
                    Button("Clear") {
                        KeychainService.delete(key: KeychainService.xaiAPIKeyName)
                        hasXAIKey = false
                    }
                }
            }

            HStack {
                SecureField("Groq API Key", text: $groqKeyInput)
                    .textFieldStyle(.roundedBorder)

                if hasGroqKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button("Save") {
                    guard !groqKeyInput.isEmpty else { return }
                    try? KeychainService.save(key: KeychainService.groqAPIKeyName, value: groqKeyInput)
                    groqKeyInput = ""
                    hasGroqKey = true
                }
                .disabled(groqKeyInput.isEmpty)

                if hasGroqKey {
                    Button("Clear") {
                        KeychainService.delete(key: KeychainService.groqAPIKeyName)
                        hasGroqKey = false
                    }
                }
            }
        }
    }

    // MARK: - Models

    private var modelsSection: some View {
        Section("Models") {
            TextField("xAI Model", text: Binding(
                get: { settings.aiModel },
                set: { settings.aiModel = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Groq Whisper Model", text: Binding(
                get: { settings.groqModel },
                set: { settings.groqModel = $0 }
            ))
            .textFieldStyle(.roundedBorder)
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
}
