import Foundation

public struct WiredApplicationInfo: Sendable {
    public let name: String?
    public let version: String?
    public let build: String?

    public init(name: String?, version: String?, build: String?) {
        self.name = Self.normalized(name)
        self.version = Self.normalized(version)
        self.build = Self.normalized(build)
    }

    public static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        processName: String = ProcessInfo.processInfo.processName
    ) -> Self {
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return Self(
            name: firstNonEmpty(
                environment["WIRED_APPLICATION_NAME"],
                displayName,
                bundleName,
                processName
            ),
            version: firstNonEmpty(
                environment["WIRED_APPLICATION_VERSION"],
                marketingVersion
            ),
            build: firstNonEmpty(
                environment["WIRED_APPLICATION_BUILD"],
                buildNumber
            )
        )
    }

    public func overriding(
        name: String? = nil,
        version: String? = nil,
        build: String? = nil
    ) -> Self {
        Self(
            name: name ?? self.name,
            version: version ?? self.version,
            build: build ?? self.build
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap(normalized).first
    }
}
