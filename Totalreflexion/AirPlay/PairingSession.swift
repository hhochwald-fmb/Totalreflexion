import CryptoKit
import Foundation

/// Legacy AirPlay pairing (pair-setup / pair-verify without PIN).
/// Produces the shared X25519 secret that is mixed into the stream keys.
final class PairingSession {
    enum PairingError: Error {
        case invalidData
        case badSignature
    }

    private let identity: ServerIdentity
    private var ourKey: Curve25519.KeyAgreement.PrivateKey?
    private var theirECDHKey = Data()
    private var theirSigningKey: Curve25519.Signing.PublicKey?
    private(set) var sharedSecret: Data?
    private(set) var isVerified = false

    init(identity: ServerIdentity) {
        self.identity = identity
    }

    /// pair-verify step 1: client sends its X25519 and Ed25519 public keys.
    /// Returns our X25519 public key followed by the encrypted signature.
    func verifyStart(_ body: Data) throws -> Data {
        let bytes = [UInt8](body)
        guard bytes.count == 4 + 32 + 32 else { throw PairingError.invalidData }
        theirECDHKey = Data(bytes[4..<36])
        theirSigningKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(bytes[36..<68]))

        let ours = Curve25519.KeyAgreement.PrivateKey()
        ourKey = ours
        let theirs = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirECDHKey)
        let secret = try ours.sharedSecretFromKeyAgreement(with: theirs).withUnsafeBytes { Data($0) }
        sharedSecret = secret

        let ourPublic = ours.publicKey.rawRepresentation
        let signature = try identity.signingKey.signature(for: ourPublic + theirECDHKey)
        let encrypted = makeCipher(secret: secret).process(signature)
        return ourPublic + encrypted
    }

    /// pair-verify step 2: client sends its encrypted signature over both ECDH keys.
    func verifyFinish(_ body: Data) throws {
        let bytes = [UInt8](body)
        guard bytes.count == 4 + 64, let secret = sharedSecret, let ourKey, let theirSigningKey else {
            throw PairingError.invalidData
        }
        let cipher = makeCipher(secret: secret)
        // The server's signature consumed the first 64 bytes of this keystream.
        _ = cipher.process(Data(count: 64))
        let signature = cipher.process(Data(bytes[4...]))
        let message = theirECDHKey + ourKey.publicKey.rawRepresentation
        guard theirSigningKey.isValidSignature(signature, for: message) else { throw PairingError.badSignature }
        isVerified = true
    }

    private func makeCipher(secret: Data) -> AESCTR {
        let key = Crypto.sha512(Data("Pair-Verify-AES-Key".utf8), secret).prefix(16)
        let iv = Crypto.sha512(Data("Pair-Verify-AES-IV".utf8), secret).prefix(16)
        return AESCTR(key: Data(key), iv: Data(iv))
    }
}

/// Wraps the reverse-engineered FairPlay SAP v1 implementation (C, from UxPlay).
final class FairPlaySession {
    private static let lock = NSLock()
    private let handle: OpaquePointer?
    private(set) var hasKeyMessage = false

    init() {
        handle = fairplay_init(nil)
    }

    deinit {
        fairplay_destroy(handle)
    }

    func setup(_ body: Data) -> RTSPResponse {
        var input = [UInt8](body)
        switch input.count {
        case 16:
            guard input[4] == 0x03 else { return .status(501, "Not Implemented") }
            var output = [UInt8](repeating: 0, count: 142)
            guard fairplay_setup(handle, &input, &output) == 0 else { return .status(500, "Internal Server Error") }
            return .binary(Data(output))
        case 164:
            var output = [UInt8](repeating: 0, count: 32)
            guard fairplay_handshake(handle, &input, &output) == 0 else { return .status(500, "Internal Server Error") }
            hasKeyMessage = true
            return .binary(Data(output))
        default:
            return .status(400, "Bad Request")
        }
    }

    /// Decrypts the 72-byte `ekey` from the first SETUP into the 16-byte session AES key.
    func decryptKey(_ ekey: Data) -> Data? {
        guard hasKeyMessage, ekey.count >= 72 else { return nil }
        var input = [UInt8](ekey.prefix(72))
        var output = [UInt8](repeating: 0, count: 16)
        // playfair keeps intermediate state in globals, so decrypt one session at a time.
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard fairplay_decrypt(handle, &input, &output) == 0 else { return nil }
        return Data(output)
    }
}
