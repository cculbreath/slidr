import SwiftUI

/// Lock screen shown at launch when vault mode is enabled.
/// Has no SwiftData dependencies — runs before ModelContainer is created.
struct VaultLockScreenView: View {
    let onUnlock: (_ password: String, _ useKeychain: Bool) async throws -> Void

    @State private var password = ""
    @State private var useKeychain = true
    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var attemptedKeychainUnlock = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Slidr Vault")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Enter your password to unlock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .disabled(isUnlocking)
                        .onSubmit { Task { await attemptUnlock() } }

                    Toggle("Remember in Keychain", isOn: $useKeychain)
                        .toggleStyle(.checkbox)
                        .foregroundStyle(.secondary)
                        .disabled(isUnlocking)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(width: 280)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await attemptUnlock() }
                    } label: {
                        HStack(spacing: 8) {
                            if isUnlocking {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isUnlocking ? "Unlocking..." : "Unlock")
                        }
                        .frame(width: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(password.isEmpty || isUnlocking)
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .task {
            guard !attemptedKeychainUnlock else { return }
            attemptedKeychainUnlock = true
            await attemptKeychainUnlock()
        }
    }

    private func attemptKeychainUnlock() async {
        guard let saved = KeychainHelper.loadPassword() else { return }
        password = saved
        await attemptUnlock()
    }

    private func attemptUnlock() async {
        guard !password.isEmpty else { return }

        isUnlocking = true
        errorMessage = nil

        do {
            try await onUnlock(password, useKeychain)
        } catch let vaultError as VaultError {
            if case .incorrectPassword = vaultError {
                errorMessage = "Incorrect password. Please try again."
                password = ""
                KeychainHelper.deletePassword()
            } else {
                errorMessage = vaultError.localizedDescription
            }
            isUnlocking = false
        } catch {
            errorMessage = error.localizedDescription
            isUnlocking = false
        }
    }
}
