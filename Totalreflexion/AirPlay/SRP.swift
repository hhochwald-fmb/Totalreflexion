import CryptoKit
import Foundation

/// Server side of the SRP-6a variant Apple uses for AirPlay PIN pairing: RFC 5054 2048-bit group, SHA-1,
/// and a 40-byte session key K = SHA1(S | 00000000) | SHA1(S | 00000001). Follows UxPlay's srp.c.
struct SRPServer {
    struct Group {
        let modulus: MontgomeryModulus
        let generator: BigUInt

        var prime: BigUInt { modulus.modulus }

        static let rfc5054Bits2048 = Group(modulus: MontgomeryModulus(BigUInt(hex: """
            AC6BDB41 324A9A9B F166DE5E 1389582F AF72B665 1987EE07 FC319294 3DB56050 A37329CB B4A099ED 8193E075 \
            7767A13D D52312AB 4B03310D CD7F48A9 DA04FD50 E8083969 EDB767B0 CF609517 9A163AB3 661A05FB D5FAAAE8 \
            2918A996 2F0B93B8 55F97993 EC975EEA A80D740A DBF4FF74 7359D041 D5C33EA7 1D281E44 6B14773B CA97B43A \
            23FB8016 76BD207A 436C6481 F1D2B907 8717461A 5B9D32E6 88F87748 544523B5 24B0D57D 5EA77A27 75D2ECFA \
            032CFBDB F52FB378 61602790 04E57AE6 AF874E73 03CE5329 9CCC041C 7BC308D8 2A5698F3 A8D0C382 71AE35F8 \
            E9DBFBB6 94B5C803 D89F7AE4 35DE236D 525F5475 9B65E372 FCD68EF2 0FA7111F 9E4AFF73
            """)), generator: BigUInt(2))
    }

    let salt: Data
    /// B, as sent to the client.
    let publicKey: Data
    private let group: Group
    private let username: String
    private let verifier: BigUInt
    private let privateKey: BigUInt
    private let publicValue: BigUInt

    init(username: String, password: String, group: Group = .rfc5054Bits2048, salt: Data? = nil,
         privateKey: Data? = nil) {
        self.group = group
        self.username = username
        // A leading zero would be dropped when hashing; the client and UxPlay expect a full 16-byte salt.
        let salt = salt ?? Self.randomBytes(16, nonZeroFirst: true)
        self.salt = salt
        let inner = Self.sha1(Data("\(username):\(password)".utf8))
        let exponent = BigUInt(Self.sha1(BigUInt(salt).bytes + inner))
        verifier = group.modulus.power(group.generator, exponent)
        self.privateKey = BigUInt(privateKey ?? Self.randomBytes(32, nonZeroFirst: false))
        let length = group.prime.bytes.count
        let multiplier = BigUInt(Self.sha1(group.prime.padded(to: length) + group.generator.padded(to: length)))
        publicValue = group.modulus.add(group.modulus.multiply(multiplier, verifier),
                                        group.modulus.power(group.generator, self.privateKey))
        publicKey = publicValue.bytes
    }

    /// Checks the client's proof M. Returns the session key K and the server proof H(A | M | K),
    /// or nil if the client used another PIN.
    func verify(clientPublicKey: Data, clientProof: Data) -> (sessionKey: Data, proof: Data)? {
        let length = group.prime.bytes.count
        let clientValue = BigUInt(clientPublicKey)
        guard clientValue.bytes.count <= length, !(clientValue % group.prime).isZero else { return nil }
        let scrambler = BigUInt(Self.sha1(clientValue.padded(to: length) + publicValue.padded(to: length)))
        let base = group.modulus.multiply(clientValue, group.modulus.power(verifier, scrambler))
        let secret = group.modulus.power(base, privateKey).bytes
        let sessionKey = Self.sha1(secret + Data([0, 0, 0, 0])) + Self.sha1(secret + Data([0, 0, 0, 1]))
        let primeHash = Self.sha1(group.prime.bytes)
        let generatorHash = Self.sha1(group.generator.bytes)
        let groupHash = Data(zip(primeHash, generatorHash).map { $0 ^ $1 })
        let expected = Self.sha1(groupHash + Self.sha1(Data(username.utf8)) + BigUInt(salt).bytes
                                 + clientValue.bytes + publicValue.bytes + sessionKey)
        guard clientProof.prefix(expected.count) == expected else { return nil }
        return (sessionKey, Self.sha1(clientValue.bytes + expected + sessionKey))
    }

    static func sha1(_ data: Data) -> Data {
        Data(Insecure.SHA1.hash(data: data))
    }

    private static func randomBytes(_ count: Int, nonZeroFirst: Bool) -> Data {
        var bytes = SymmetricKey(size: SymmetricKeySize(bitCount: count * 8)).withUnsafeBytes { Data($0) }
        if nonZeroFirst, bytes[bytes.startIndex] == 0 {
            bytes[bytes.startIndex] = 1
        }
        return bytes
    }
}

/// The three pair-setup-pin requests of one connection ("Code auf dem Bildschirm").
final class PinPairing {
    enum Outcome {
        case reply([String: Any])
        /// Step 3 succeeded: the client is now paired with this Ed25519 public key.
        case paired(reply: [String: Any], clientKey: Data)
        case failed
    }

    private var server: SRPServer?
    private var sessionKey: Data?

    /// - Parameters:
    ///   - pin: the code currently shown on screen; nil if none is shown.
    ///   - serverKey: our Ed25519 public key, sent back encrypted in step 3.
    func handle(_ body: [String: Any], pin: String?, serverKey: Data) -> Outcome {
        if let method = body["method"] as? String, let user = body["user"] as? String {
            // Step 1: the client names itself; answer with salt and B for the current PIN.
            guard method == "pin", let pin else { return .failed }
            let server = SRPServer(username: user, password: pin)
            self.server = server
            return .reply(["pk": server.publicKey, "salt": server.salt])
        }
        if let clientKey = body["pk"] as? Data, let proof = body["proof"] as? Data {
            // Step 2: the client proves it knows the PIN.
            guard let result = server?.verify(clientPublicKey: clientKey, clientProof: proof) else {
                server = nil
                return .failed
            }
            sessionKey = result.sessionKey
            return .reply(["proof": result.proof])
        }
        if let encryptedKey = body["epk"] as? Data, let tag = body["authTag"] as? Data, let sessionKey {
            // Step 3: exchange Ed25519 public keys, encrypted with the SRP session key.
            self.sessionKey = nil
            server = nil
            return exchangeKeys(encryptedKey: encryptedKey, tag: tag, sessionKey: sessionKey, serverKey: serverKey)
        }
        return .failed
    }

    private func exchangeKeys(encryptedKey: Data, tag: Data, sessionKey: Data, serverKey: Data) -> Outcome {
        let key = SymmetricKey(data: Data(SHA512.hash(data: Data("Pair-Setup-AES-Key".utf8) + sessionKey)).prefix(16))
        var nonce = [UInt8](Data(SHA512.hash(data: Data("Pair-Setup-AES-IV".utf8) + sessionKey)).prefix(16))
        nonce[15] &+= 1
        guard let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: encryptedKey, tag: tag),
              let clientKey = try? AES.GCM.open(box, using: key) else { return .failed }
        // The reply uses the next nonce.
        nonce[15] &+= 1
        guard let reply = try? AES.GCM.seal(serverKey, using: key, nonce: AES.GCM.Nonce(data: nonce)) else {
            return .failed
        }
        return .paired(reply: ["epk": reply.ciphertext, "authTag": reply.tag], clientKey: clientKey)
    }
}
