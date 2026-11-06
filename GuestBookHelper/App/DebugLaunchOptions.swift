#if DEBUG
import Foundation

enum DebugLaunchOptions {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var route: String? {
        guard let index = arguments.firstIndex(of: "-ui-route"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var forceDark: Bool { arguments.contains("-ui-dark") }
    static var forceLight: Bool { arguments.contains("-ui-light") }
    static var seedTags: Bool { arguments.contains("-ui-seed-tags") }

    static var searchText: String? {
        guard let index = arguments.firstIndex(of: "-ui-search"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
#endif
