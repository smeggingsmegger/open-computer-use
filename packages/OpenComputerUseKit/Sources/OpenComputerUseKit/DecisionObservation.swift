import Foundation

extension AppSnapshot {
    // Capture-time records only: no second AX read, field values, or geometry.
    // These records describe candidates; cached identity review still owns input.
    var decisionObservationJSON: String? {
        let controls: [[String: Any]] = elements.values.sorted { $0.index < $1.index }.compactMap { record in
            let role = record.role ?? ""
            guard !record.isSyntheticText, !role.localizedCaseInsensitiveContains("secure"),
                  !(record.identityEvidence?.attributes["AXSubrole"] ?? "").localizedCaseInsensitiveContains("secure") else { return nil }
            return [
                "index": record.index,
                "role": role,
                "name": String((record.decisionLabel ?? record.identifier ?? "").prefix(240)),
                "actions": record.rawActions,
                "editable": ["AXTextField", "AXTextArea", "AXComboBox", "textField", "textArea"].contains(role),
            ]
        }
        let envelope: [String: Any] = ["taffy_observation": [
            "version": 1,
            "window": String((windowTitle ?? "").prefix(240)),
            "elements": controls,
            "text": controls.filter { ($0["role"] as? String ?? "").localizedCaseInsensitiveContains("statictext") }.compactMap { $0["name"] as? String }.joined(separator: "\n"),
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
