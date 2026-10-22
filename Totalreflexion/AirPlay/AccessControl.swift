import CryptoKit
import Foundation

/// How iPads must authenticate before they may mirror.
enum AccessMode: String, CaseIterable, Identifiable {
    case open
    case code
    case password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Ohne"
        case .code: "Code auf dem Bildschirm"
        case .password: "Passwort"
        }
    }
}

/// Shared by all sessions, each running on its own queue: the active mode, the code currently shown,
/// open password challenges and the iPads already paired with a code.
final class AccessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var mode: AccessMode = .open
    private var password = ""
    private var shownCode: String?
    /// Nonces of recent password challenges; several iPads may be asked at the same time.
    private var nonces: [String] = []
    /// Base64 Ed25519 public keys of iPads paired with a code; they reconnect without a code.
    private var pairedKeys: Set<String>
    private let defaultsKey = "pairedClients"

    /// Called on a session queue with the code to show, or nil once it is no longer needed.
    var onCodeChange: (String?) -> Void = { _ in }

    init() {
        pairedKeys = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    /// A password mode without a password would lock everybody out, so it counts as open.
    func configure(mode: AccessMode, password: String) {
        locked {
            self.mode = mode == .password && password.isEmpty ? .open : mode
            self.password = password
            shownCode = nil
            nonces = []
        }
    }

    var effectiveMode: AccessMode { locked { mode } }

    var pairedCount: Int { locked { pairedKeys.count } }

    // MARK: - Code on screen

    /// Picks a new 4-digit code and shows it.
    func showNewCode() {
        let code = String(format: "%04d", Int.random(in: 0...9999))
        locked { shownCode = code }
        onCodeChange(code)
    }

    var currentCode: String? { locked { shownCode } }

    func isPaired(_ clientKey: Data) -> Bool {
        locked { pairedKeys.contains(clientKey.base64EncodedString()) }
    }

    func pair(_ clientKey: Data) {
        let keys = locked {
            pairedKeys.insert(clientKey.base64EncodedString())
            shownCode = nil
            return Array(pairedKeys)
        }
        UserDefaults.standard.set(keys, forKey: defaultsKey)
        onCodeChange(nil)
    }

    func forgetPairings() {
        locked { pairedKeys = [] }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    // MARK: - Password (RFC 2617 digest, as UxPlay does it)

    /// Returns nil if the request may proceed, otherwise the WWW-Authenticate challenge for a 401 response.
    func passwordChallenge(method: String, authorization: String?) -> String? {
        locked {
            guard mode == .password else { return nil }
            if let authorization {
                let fields = Self.digestFields(authorization)
                if let nonce = fields["nonce"], let index = nonces.firstIndex(of: nonce),
                   Self.digestMatches(fields, method: method, password: password) {
                    nonces.remove(at: index)
                    return nil
                }
            }
            let nonce = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }
                .joined()
            nonces = Array((nonces + [nonce]).suffix(8))
            return "Digest realm=\"raop\", nonce=\"\(nonce)\""
        }
    }

    static func digestMatches(_ fields: [String: String], method: String, password: String) -> Bool {
        guard let username = fields["username"], let realm = fields["realm"], let nonce = fields["nonce"],
              let uri = fields["uri"], let response = fields["response"] else { return false }
        let first = md5("\(username):\(realm):\(password)")
        let second = md5("\(method):\(uri)")
        let expected = if let qop = fields["qop"], let count = fields["nc"], let clientNonce = fields["cnonce"] {
            md5("\(first):\(nonce):\(count):\(clientNonce):\(qop):\(second)")
        } else {
            md5("\(first):\(nonce):\(second)")
        }
        return expected == response.lowercased()
    }

    /// Parses `Digest key="value", key=value, …`.
    static func digestFields(_ header: String) -> [String: String] {
        var text = header.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("digest ") {
            text.removeFirst(7)
        }
        var fields: [String: String] = [:]
        var remainder = Substring(text)
        while let equals = remainder.firstIndex(of: "=") {
            let key = remainder[..<equals].trimmingCharacters(in: CharacterSet(charactersIn: " ,")).lowercased()
            remainder = remainder[remainder.index(after: equals)...]
            let value: Substring
            if remainder.first == "\"" {
                remainder = remainder.dropFirst()
                let end = remainder.firstIndex(of: "\"") ?? remainder.endIndex
                value = remainder[..<end]
                remainder = end < remainder.endIndex ? remainder[remainder.index(after: end)...] : ""
            } else {
                let end = remainder.firstIndex(of: ",") ?? remainder.endIndex
                value = remainder[..<end]
                remainder = remainder[end...]
            }
            fields[key] = value.trimmingCharacters(in: .whitespaces)
        }
        return fields
    }

    private static func md5(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
