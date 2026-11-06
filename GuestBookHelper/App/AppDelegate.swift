import SwiftUI
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let appState = AppState()
    private var lastIncomingURL: URL?
    private var lastIncomingAt: Date = .distantPast

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let rootView = RootView().environmentObject(appState)
        let controller = UIHostingController(rootView: rootView)
        controller.view.backgroundColor = AppTheme.canvasUIColor

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = AppTheme.canvasUIColor
        window.overrideUserInterfaceStyle = appState.appearance.userInterfaceStyle
        window.rootViewController = controller
        self.window = window

        appState.onAppearanceChange = { [weak self] style in
            guard let self = self else { return }
            if #available(iOS 13.0, *) {
                self.window?.overrideUserInterfaceStyle = style
            }
            UIView.animate(withDuration: 0.2) {
                self.window?.rootViewController?.view.layoutIfNeeded()
            }
        }

        window.makeKeyAndVisible()

        // Cold launch from the system share sheet / "Open in" menu.
        if let url = launchOptions?[.url] as? URL {
            _ = acceptIncomingURL(url)
        }
        return true
    }

    // Warm launch from the share sheet / Files / Mail.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        acceptIncomingURL(url)
    }

    @discardableResult
    private func acceptIncomingURL(_ url: URL) -> Bool {
        guard url.isFileURL,
              ["xlsx", "ngbd"].contains(url.pathExtension.lowercased()) else { return false }
        let now = Date()
        if let lastIncomingURL = lastIncomingURL,
           lastIncomingURL == url,
           now.timeIntervalSince(lastIncomingAt) < 3 {
            return true
        }
        lastIncomingURL = url
        lastIncomingAt = now
        appState.enqueueImport([url])
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return .allButUpsideDown
    }
}
