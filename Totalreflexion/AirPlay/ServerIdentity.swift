import CryptoKit
import Foundation

/// Stable identity of this receiver. iPads remember receivers by device ID and public key,
/// so both are generated once and persisted.
struct ServerIdentity {
    let signingKey: Curve25519.Signing.PrivateKey
    /// Six bytes, formatted like a MAC address.
    let deviceID: [UInt8]
    let pairingIdentifier: String

    var publicKey: Data { signingKey.publicKey.rawRepresentation }
    var publicKeyHex: String { publicKey.map { String(format: "%02x", $0) }.joined() }
    var deviceIDString: String { deviceID.map { String(format: "%02X", $0) }.joined(separator: ":") }
    var deviceIDHex: String { deviceID.map { String(format: "%02X", $0) }.joined() }

    static func loadOrCreate(defaults: UserDefaults = .standard) -> ServerIdentity {
        let key: Curve25519.Signing.PrivateKey
        if let raw = defaults.data(forKey: "identity.signingKey"),
           let stored = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            key = stored
        } else {
            key = Curve25519.Signing.PrivateKey()
            defaults.set(key.rawRepresentation, forKey: "identity.signingKey")
        }

        var deviceID: [UInt8]
        if let stored = defaults.data(forKey: "identity.deviceID"), stored.count == 6 {
            deviceID = [UInt8](stored)
        } else {
            deviceID = (0..<6).map { _ in UInt8.random(in: 0...255) }
            // Locally administered unicast address, so it never collides with real hardware.
            deviceID[0] = (deviceID[0] & 0xFC) | 0x02
            defaults.set(Data(deviceID), forKey: "identity.deviceID")
        }

        let pairingIdentifier: String
        if let stored = defaults.string(forKey: "identity.pi") {
            pairingIdentifier = stored
        } else {
            pairingIdentifier = UUID().uuidString.lowercased()
            defaults.set(pairingIdentifier, forKey: "identity.pi")
        }

        return ServerIdentity(signingKey: key, deviceID: deviceID, pairingIdentifier: pairingIdentifier)
    }
}
