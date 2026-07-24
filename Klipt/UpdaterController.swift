import Foundation
import Sparkle

@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private let isTesting: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        isTesting = environment["XCTestConfigurationFilePath"] != nil
        controller = SPUStandardUpdaterController(
            startingUpdater: !isTesting,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        guard !isTesting else { return }
        controller.checkForUpdates(nil)
    }
}
