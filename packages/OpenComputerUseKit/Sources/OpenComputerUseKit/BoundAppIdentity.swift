import AppKit
import Foundation
import Security

/// Private host contract. Metadata is supplied by the host after its own user
/// authorization; accepting this contract does not infer consent from app data.
final class BoundAppIdentity {
    let expected: InstalledAppIdentity

    init(_ expected: InstalledAppIdentity) throws {
        self.expected = expected
        try validateInstalled()
        _ = try Self.codeRequirement(expected.signing)
    }

    func validateInstalled() throws {
        guard expected.platform == "macos",
              try InstalledAppIdentity.inspect(URL(fileURLWithPath: expected.bundlePath)) == expected else {
            throw ComputerUseError.permissionDenied("The approved app installation changed. Review its identity again before continuing.")
        }
    }

    static func codeRequirement(_ signing: AppSigningMetadata) throws -> SecRequirement {
        guard ["valid_signature", "ad_hoc"].contains(signing.status),
              let hash = signing.codeDirectoryHash, hash.count == 40,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw ComputerUseError.permissionDenied("This app has no verifiable signed code identity. Repair its installation or use another approved app.")
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(hash)\"" as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement else {
            throw ComputerUseError.permissionDenied("The approved app code identity cannot be checked.")
        }
        return requirement
    }

    static func validateProcessCode(pid: pid_t, signing: AppSigningMetadata) throws {
        let requirement = try codeRequirement(signing)
        var code: SecCode?
        guard pid > 0,
              SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid as String: pid] as CFDictionary, SecCSFlags(), &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, .noNetworkAccess, requirement) == errSecSuccess else {
            throw ComputerUseError.permissionDenied("The running app does not match the approved code identity. Inspect and approve the current app before continuing.")
        }
    }

    func validate(_ app: RunningAppDescriptor) throws {
        guard snapshotAppIsCurrent(app), app.bundleIdentifier == expected.bundleIdentifier,
              app.runningApplication.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == expected.bundlePath,
              app.snapshotProcessIdentity.executablePath == expected.executablePath else {
            throw ComputerUseError.permissionDenied("The running app target changed. Inspect the approved app again before continuing.")
        }
        try Self.validateProcessCode(pid: app.pid, signing: expected.signing)
        guard snapshotAppIsCurrent(app) else {
            throw ComputerUseError.permissionDenied("The app process changed while checking its identity. Inspect it again before continuing.")
        }
    }

    func resolveForInspection() throws -> RunningAppDescriptor {
        try validateInstalled()
        func candidates() -> [RunningAppDescriptor] {
            AppDiscovery.runningApps().filter {
                $0.runningApplication.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == expected.bundlePath
            }
        }
        var apps = candidates()
        if apps.isEmpty {
            // Launch exactly the reviewed installation, without activating it.
            try AppDiscovery.openApplication(at: URL(fileURLWithPath: expected.bundlePath), activate: false)
            for _ in 0..<20 {
                apps = candidates()
                if !apps.isEmpty { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        guard apps.count == 1, let app = apps.first else {
            throw ComputerUseError.stateUnavailable("The approved app has no unique running instance. Select one instance before continuing.")
        }
        try validate(app)
        return app
    }

    static func decode(_ object: [String: Any]) throws -> InstalledAppIdentity {
        let keys: Set<String> = ["platform", "name", "bundle_identifier", "bundle_path", "executable_path", "signing"]
        let signingKeys: Set<String> = ["status", "team_identifier", "designated_requirement", "code_directory_hash"]
        guard Set(object.keys) == keys, let signing = object["signing"] as? [String: Any],
              Set(signing.keys).isSubset(of: signingKeys), signing["status"] is String else {
            throw ComputerUseError.invalidArguments("Unsupported app identity fields; refresh app identity with this helper version.")
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= 1_048_576 else { throw ComputerUseError.invalidArguments("App identity is too large.") }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(InstalledAppIdentity.self, from: data)
    }
}
