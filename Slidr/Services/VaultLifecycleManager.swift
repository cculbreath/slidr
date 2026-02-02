import Foundation
import AppKit
import OSLog

/// Monitors system events and auto-locks vaults on sleep, screensaver, or idle timeout.
@MainActor
final class VaultLifecycleManager {
    private let vaultService: VaultService
    private let onLockRequired: () async -> Void

    private var sleepObserver: NSObjectProtocol?
    private var screensaverObserver: NSObjectProtocol?
    private var idleTimer: Timer?

    init(vaultService: VaultService, onLockRequired: @escaping () async -> Void) {
        self.vaultService = vaultService
        self.onLockRequired = onLockRequired
    }

    func startMonitoring(autoLockOnSleep: Bool, autoLockOnScreensaver: Bool, lockTimeoutMinutes: Int?) {
        stopMonitoring()

        if autoLockOnSleep {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAutoLock(reason: "system sleep")
                }
            }
        }

        if autoLockOnScreensaver {
            screensaverObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screensaver.didstart"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAutoLock(reason: "screensaver")
                }
            }
        }

        if let minutes = lockTimeoutMinutes, minutes > 0 {
            idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAutoLock(reason: "idle timeout")
                }
            }
        }

        Logger.vault.info("Vault lifecycle monitoring started")
    }

    func stopMonitoring() {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = screensaverObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screensaverObserver = nil
        }
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func handleAutoLock(reason: String) async {
        Logger.vault.info("Auto-lock triggered: \(reason)")
        await onLockRequired()
    }

    deinit {
        // Observers will be cleaned up by stopMonitoring() called from AppLauncher.lock()
    }
}
