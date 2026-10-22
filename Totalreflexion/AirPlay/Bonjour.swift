import dnssd
import Foundation
import os

enum AirPlayConstants {
    static let model = "AppleTV3,2"
    static let sourceVersion = "220.68"
    /// Bit 27 ("supports legacy pairing") stays on: every iPad gets its own pairing session and keys,
    /// which is what makes several simultaneous mirroring clients possible.
    static let features: UInt64 = 0x5A7F_FEE6
    static var featuresString: String {
        String(format: "0x%X,0x%X", UInt32(features & 0xFFFF_FFFF), UInt32(features >> 32))
    }
}

/// Builds DNS-SD TXT records (also returned verbatim from GET /info).
struct TXTRecord {
    private(set) var entries: [(String, String)] = []

    mutating func set(_ key: String, _ value: String) {
        entries.append((key, value))
    }

    var data: Data {
        var result = Data()
        for (key, value) in entries {
            let entry = Data("\(key)=\(value)".utf8).prefix(255)
            result.append(UInt8(entry.count))
            result.append(entry)
        }
        return result
    }

    static func airPlay(identity: ServerIdentity) -> TXTRecord {
        var txt = TXTRecord()
        txt.set("deviceid", identity.deviceIDString)
        txt.set("features", AirPlayConstants.featuresString)
        txt.set("flags", "0x4")
        txt.set("model", AirPlayConstants.model)
        txt.set("pk", identity.publicKeyHex)
        txt.set("pi", identity.pairingIdentifier)
        txt.set("srcvers", AirPlayConstants.sourceVersion)
        txt.set("vv", "2")
        return txt
    }

    static func raop(identity: ServerIdentity) -> TXTRecord {
        var txt = TXTRecord()
        txt.set("ch", "2")
        txt.set("cn", "0,1,2,3")
        txt.set("da", "true")
        txt.set("et", "0,3,5")
        txt.set("vv", "2")
        txt.set("ft", AirPlayConstants.featuresString)
        txt.set("am", AirPlayConstants.model)
        txt.set("md", "0,1,2")
        txt.set("rhd", "5.6.0.0")
        txt.set("pw", "false")
        txt.set("sf", "0x4")
        txt.set("sr", "44100")
        txt.set("ss", "16")
        txt.set("sv", "false")
        txt.set("tp", "UDP")
        txt.set("txtvers", "1")
        txt.set("vs", AirPlayConstants.sourceVersion)
        txt.set("vn", "65537")
        txt.set("pk", identity.publicKeyHex)
        return txt
    }
}

/// Advertises the receiver as `_airplay._tcp` (screen mirroring) and `_raop._tcp` (audio).
final class BonjourAdvertiser {
    private var airplayRef: DNSServiceRef?
    private var raopRef: DNSServiceRef?
    private let queue = DispatchQueue(label: "Totalreflexion.bonjour")
    private let log = Logger(subsystem: "Totalreflexion", category: "Bonjour")

    func start(name: String, port: UInt16, identity: ServerIdentity) {
        stop()
        airplayRef = register(name: name, type: "_airplay._tcp", port: port,
                              txt: TXTRecord.airPlay(identity: identity).data)
        raopRef = register(name: "\(identity.deviceIDHex)@\(name)", type: "_raop._tcp", port: port,
                           txt: TXTRecord.raop(identity: identity).data)
    }

    func stop() {
        for ref in [airplayRef, raopRef].compactMap({ $0 }) {
            DNSServiceRefDeallocate(ref)
        }
        airplayRef = nil
        raopRef = nil
    }

    private func register(name: String, type: String, port: UInt16, txt: Data) -> DNSServiceRef? {
        var ref: DNSServiceRef?
        let error = txt.withUnsafeBytes { bytes in
            DNSServiceRegister(&ref, 0, 0, name, type, nil, nil, port.bigEndian,
                               UInt16(txt.count), bytes.baseAddress, nil, nil)
        }
        guard error == kDNSServiceErr_NoError, let ref else {
            log.error("DNSServiceRegister \(type, privacy: .public) failed: \(error)")
            return nil
        }
        DNSServiceSetDispatchQueue(ref, queue)
        log.info("Advertising \(name, privacy: .public) as \(type, privacy: .public) on port \(port)")
        return ref
    }

    deinit {
        stop()
    }
}
