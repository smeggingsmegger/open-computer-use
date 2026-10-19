import ApplicationServices
import Foundation

// Values stay private to the snapshot. This detects a recycled control; it is
// not an effect classifier, a form digest, or permission to operate the control.
struct ElementIdentityEvidence: Equatable {
    let attributes: [String: String]

    static func capture(_ element: AXUIElement) -> ElementIdentityEvidence? {
        capture { name in
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (result, value)
        }
    }

    static func capture(read: (String) -> (AXError, CFTypeRef?)) -> ElementIdentityEvidence? {
        var attributes: [String: String] = [:]
        for name in [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute,
                     kAXTitleAttribute, kAXDescriptionAttribute, kAXURLAttribute] {
            let (result, value) = read(name)
            if result == .attributeUnsupported || result == .noValue { continue }
            guard result == .success else { return nil }
            // AX links may expose CFURL or String. The destination is part of
            // target identity even when the visible label is unchanged.
            let text = name == kAXURLAttribute
                ? (value as? URL)?.absoluteString ?? (value as? String)
                : value as? String
            guard let text, text.utf8.count <= 4096 else { return nil }
            attributes[name] = text
        }
        guard attributes[kAXRoleAttribute] != nil else { return nil }
        return ElementIdentityEvidence(attributes: attributes)
    }

    static func requireCurrent(_ observed: ElementIdentityEvidence?, current: () -> ElementIdentityEvidence?) throws {
        guard let observed, let current = current(), observed == current else {
            throw ComputerUseError.stateUnavailable("The inspected control changed or is no longer available. Run get_app_state and review the current target before acting.")
        }
    }
}
