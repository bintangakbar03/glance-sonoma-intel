// The upstream feed distributes builds with a newer macOS target.
// This Sonoma port is updated manually and never installs those builds.
// Keep the interface used by the menu bar and Settings without loading Sparkle.

import Observation

@Observable
@MainActor
final class UpdaterController {
    var canCheckForUpdates: Bool { false }
    var isPresentingUpdateUI: Bool { false }

    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { /* Manual updates only in this build. */ }
    }

    func start() {}
    func checkForUpdates() {}
}
