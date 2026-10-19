import AppKit
import Foundation
import Security

struct AppSigningMetadata: Codable, Equatable {
    let status: String
    let teamIdentifier: String?
    let designatedRequirement: String?
    let codeDirectoryHash: String?

    static func inspect(_ url: URL) -> Self {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess, let code else {
            return Self(status: "unavailable", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: nil)
        }
        let validation = SecStaticCodeCheckValidity(code, SecCSFlags.noNetworkAccess.union(SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)), nil)
        guard validation == errSecSuccess else {
            return Self(status: validation == errSecCSUnsigned ? "unsigned" : "invalid", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: nil)
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let details = info as? [String: Any] else {
            return Self(status: "unavailable", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: nil)
        }
        var requirement: SecRequirement?
        var requirementText: CFString?
        if SecCodeCopyDesignatedRequirement(code, SecCSFlags(), &requirement) == errSecSuccess, let requirement {
            _ = SecRequirementCopyString(requirement, SecCSFlags(), &requirementText)
        }
        guard let signatureFlags = (details[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value,
              let requirementText = requirementText as String?, !requirementText.isEmpty,
              let codeHash = details[kSecCodeInfoUnique as String] as? Data, !codeHash.isEmpty else {
            return Self(status: "unavailable", teamIdentifier: nil, designatedRequirement: nil, codeDirectoryHash: nil)
        }
        let adhoc = signatureFlags & SecCodeSignatureFlags.adhoc.rawValue != 0
        let hash = codeHash.map { String(format: "%02x", $0) }.joined()
        return Self(status: adhoc ? "ad_hoc" : "valid_signature", teamIdentifier: details[kSecCodeInfoTeamIdentifier as String] as? String,
                    designatedRequirement: requirementText, codeDirectoryHash: hash)
    }
}

/// Installed code metadata only. This is not proof of a running process's code
/// identity, Gatekeeper approval, or user authorization to inspect/control it.
struct InstalledAppIdentity: Codable, Equatable {
    let platform: String
    let name: String
    let bundleIdentifier: String
    let bundlePath: String
    let executablePath: String
    let signing: AppSigningMetadata

    static func inspect(_ candidate: URL) throws -> Self {
        let url = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
              let executable = bundle.executableURL?.resolvingSymlinksInPath().standardizedFileURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ComputerUseError.stateUnavailable("App identity is incomplete; select an installed application bundle.")
        }
        guard !AppSafetyPolicy.isBlocked(bundleIdentifier: identifier) else {
            throw AppSafetyPolicy.permissionDenied(bundleIdentifier: identifier)
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return Self(platform: "macos", name: name, bundleIdentifier: identifier, bundlePath: url.path,
                    executablePath: executable.path, signing: AppSigningMetadata.inspect(url))
    }
}

struct AppIdentityResolution: Codable {
    let version: Int
    let status: String
    let candidates: [InstalledAppIdentity]

    var asDictionary: [String: Any] {
        get throws {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(self)
            guard data.count <= 1_048_576 else { throw ComputerUseError.stateUnavailable("App identity metadata is too large; select another app or repair its installation.") }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }
    }
}

enum AppIdentityResolver {
    static func resolve(_ query: String) throws -> AppIdentityResolution {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 1024 else {
            throw ComputerUseError.invalidArguments("Name an app, its bundle identifier, or its exact .app path.")
        }
        if query.hasPrefix("/") {
            return try resolveCandidates([URL(fileURLWithPath: query)])
        }
        var matches = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: query)
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            if app.localizedName?.caseInsensitiveCompare(query) == .orderedSame
                || app.bundleIdentifier?.caseInsensitiveCompare(query) == .orderedSame
                || app.executableURL?.lastPathComponent.caseInsensitiveCompare(query) == .orderedSame,
               let url = app.bundleURL { matches.append(url) }
        }
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        let started = ProcessInfo.processInfo.systemUptime
        var visited = 0
        for root in roots {
            guard let files = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files {
                visited += 1
                guard visited <= 20_000, ProcessInfo.processInfo.systemUptime - started < 3 else {
                    throw ComputerUseError.stateUnavailable("App lookup reached its limit; use the exact .app path to select the application.")
                }
                guard url.pathExtension.lowercased() == "app" else { continue }
                let bundle = Bundle(url: url)
                let names = [url.lastPathComponent, url.deletingPathExtension().lastPathComponent, bundle?.bundleIdentifier, bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String, bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String].compactMap { $0 }
                if names.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) { matches.append(url) }
            }
        }
        return try resolveCandidates(matches)
    }

    static func resolveCandidates(_ urls: [URL]) throws -> AppIdentityResolution {
        let paths = Set(urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }).sorted()
        guard paths.count <= 8 else {
            throw ComputerUseError.stateUnavailable("Several app copies match; select the exact .app path.")
        }
        let identities = try paths.map { try InstalledAppIdentity.inspect(URL(fileURLWithPath: $0)) }
        return AppIdentityResolution(version: 1, status: identities.isEmpty ? "not_found" : identities.count == 1 ? "resolved" : "ambiguous", candidates: identities)
    }
}
