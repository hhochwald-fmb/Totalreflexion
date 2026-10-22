import CoreVideo
import Foundation
import Network
import os

struct ReceiverConfiguration {
    var name: String
    var identity: ServerIdentity
    var width: Int
    var height: Int
    var maxFPS: Int
    var audioEnabled: Bool
    var access: AccessControl
}

protocol AirPlaySessionDelegate: AnyObject {
    /// The iPad identified itself in its first SETUP. Returns the frame sink for its video.
    func sessionDidStart(_ session: AirPlaySession, deviceID: String, name: String, model: String) -> FrameSource
    func session(_ session: AirPlaySession, videoSizeChanged size: CGSize)
    func session(_ session: AirPlaySession, suspended: Bool)
    func session(_ session: AirPlaySession, volumeChanged volume: Float)
    func sessionDidEnd(_ session: AirPlaySession)
}

/// One AirPlay control connection = one mirroring iPad. Every session has its own pairing,
/// FairPlay state, keys and stream ports, so any number of devices can mirror at once.
final class AirPlaySession {
    let id = UUID()
    let remoteDescription: String
    weak var delegate: AirPlaySessionDelegate?

    private let connection: NWConnection
    private let configuration: ReceiverConfiguration
    private let queue: DispatchQueue
    private let log = Logger(subsystem: "Totalreflexion", category: "Session")
    private let remoteAddress: RemoteAddress?

    private var receiveBuffer = Data()
    private let pairing: PairingSession
    private let pinPairing = PinPairing()
    private var passwordAccepted = false
    private let fairPlay = FairPlaySession()
    private var sessionKey: Data?
    private var audioIV: Data?
    private var started = false
    private var ended = false

    private var timing: TimingClient?
    private var mirrorListener: TCPStreamListener?
    private var mirrorParser: MirrorStreamParser?
    private var decoder: VideoDecoder?
    private var frameSource: FrameSource?
    private var audio: AudioReceiver?
    private var lastVideoSize = CGSize.zero
    private var localVolume: Float = 1

    init(connection: NWConnection, configuration: ReceiverConfiguration) {
        self.connection = connection
        self.configuration = configuration
        queue = DispatchQueue(label: "Totalreflexion.session.\(UUID().uuidString.prefix(8))")
        pairing = PairingSession(identity: configuration.identity)
        remoteAddress = RemoteAddress(endpoint: connection.endpoint)
        remoteDescription = "\(connection.endpoint)"
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.teardown()
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    /// Ends mirroring from the Mac side.
    func stop() {
        queue.async { self.teardown() }
    }

    /// Local mute/volume, multiplied with the iPad's own volume.
    func setLocalVolume(_ volume: Float) {
        queue.async {
            self.localVolume = volume
            self.audio?.localVolume = volume
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                receiveBuffer.append(data)
                processBuffer()
            }
            if isComplete || error != nil {
                teardown()
            } else {
                receive()
            }
        }
    }

    private func processBuffer() {
        while let (request, consumed) = RTSPRequest.parse(receiveBuffer) {
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<(receiveBuffer.startIndex + consumed))
            var response = handle(request)
            if request.header("CSeq") != nil, request.method != "RECORD" {
                response.headers.append(("Audio-Jack-Status", "connected; type=digital"))
            }
            connection.send(content: response.serialized(for: request), completion: .contentProcessed { _ in })
            if response.disconnect {
                teardown()
                return
            }
        }
    }

    // MARK: - Request handlers

    private func handle(_ request: RTSPRequest) -> RTSPResponse {
        log.debug("\(request.method, privacy: .public) \(request.path, privacy: .public)")
        switch request.method {
        case "GET" where request.path == "/info":
            return handleInfo(request)
        case "POST":
            return handlePost(request)
        case "OPTIONS":
            return .options
        case "SETUP":
            return handleSetup(request)
        case "GET_PARAMETER":
            return .volumeParameter
        case "SET_PARAMETER":
            handleSetParameter(request)
            return .ok
        case "RECORD":
            return .record
        case "TEARDOWN":
            return handleTeardown(request)
        default:
            // FLUSH and friends just need an OK.
            return .ok
        }
    }

    private func handlePost(_ request: RTSPRequest) -> RTSPResponse {
        switch request.path {
        case "/pair-setup":
            guard request.body.count == 32 else { return .status(400, "Bad Request") }
            return .binary(configuration.identity.publicKey)
        case "/pair-verify":
            return handlePairVerify(request)
        case "/pair-pin-start":
            // The iPad asks for a code: show a fresh one on screen.
            guard configuration.access.effectiveMode == .code else { return .status(404, "Not Found") }
            configuration.access.showNewCode()
            return .ok
        case "/pair-setup-pin":
            return handlePairSetupPin(request)
        case "/fp-setup":
            return fairPlay.setup(request.body)
        default:
            // /feedback (heartbeat), /audioMode: acknowledge.
            return .ok
        }
    }

    private func handleInfo(_ request: RTSPRequest) -> RTSPResponse {
        var info: [String: Any] = [:]
        if let qualifier = (request.plistBody?["qualifier"] as? [String])?.first {
            let access = configuration.access.effectiveMode
            if qualifier == "txtAirPlay" {
                info["txtAirPlay"] = TXTRecord.airPlay(identity: configuration.identity, access: access).data
            } else if qualifier == "txtRAOP" {
                info["txtRAOP"] = TXTRecord.raop(identity: configuration.identity, access: access).data
            }
        }
        if request.header("Content-Type") != nil {
            return .plist(info)
        }

        let identity = configuration.identity
        info["deviceID"] = identity.deviceIDString
        info["macAddress"] = identity.deviceIDString
        info["pk"] = identity.publicKey
        info["features"] = AirPlayConstants.features
        info["name"] = configuration.name
        info["pi"] = identity.pairingIdentifier
        info["vv"] = 2
        info["statusFlags"] = 68
        info["keepAliveLowPower"] = true
        info["keepAliveSendStatsAsBody"] = true
        info["sourceVersion"] = AirPlayConstants.sourceVersion
        info["model"] = AirPlayConstants.model
        info["initialVolume"] = 0.0
        let latency: (Int) -> [String: Any] = { type in
            ["type": type, "audioType": "default", "inputLatencyMicros": 0, "outputLatencyMicros": false]
        }
        info["audioLatencies"] = [latency(100), latency(101)]
        let format: (Int) -> [String: Any] = { type in
            ["type": type, "audioInputFormats": 0x3FF_FFFC, "audioOutputFormats": 0x3FF_FFFC]
        }
        info["audioFormats"] = [format(100), format(101)]
        info["displays"] = [[
            "uuid": "e0ff8a27-6738-3d56-8a16-cc53aacee925",
            "widthPhysical": 0, "heightPhysical": 0,
            "width": configuration.width, "height": configuration.height,
            "widthPixels": configuration.width, "heightPixels": configuration.height,
            "rotation": false,
            "refreshRate": 1.0 / Double(configuration.maxFPS),
            "maxFPS": configuration.maxFPS,
            "overscanned": false,
            "features": 14
        ] as [String: Any]]
        return .plist(info)
    }

    private func handleSetup(_ request: RTSPRequest) -> RTSPResponse {
        guard let body = request.plistBody else { return .status(400, "Bad Request") }
        var result: [String: Any] = [:]

        if let ekey = body["ekey"] as? Data, let eiv = body["eiv"] as? Data {
            // With a password, the first SETUP is answered with a digest challenge until the iPad sends it.
            if !passwordAccepted {
                if let challenge = configuration.access.passwordChallenge(
                    method: request.method, authorization: request.header("Authorization")) {
                    var response = RTSPResponse.status(401, "Unauthorized")
                    response.headers.append(("WWW-Authenticate", challenge))
                    return response
                }
                passwordAccepted = true
            }
            guard setupKeys(ekey: ekey, eiv: eiv) else {
                log.error("FairPlay key decryption failed")
                return .status(500, "Internal Server Error")
            }
            if let remoteAddress, let port = (body["timingPort"] as? NSNumber)?.uint16Value, port != 0 {
                timing = TimingClient(queue: queue, remote: remoteAddress.with(port: port))
            }
            result["timingPort"] = Int(timing?.localPort ?? 0)
            result["eventPort"] = 0
            identify(body)
        }

        if let streams = body["streams"] as? [[String: Any]] {
            guard let streamResults = setupStreams(streams) else { return .status(500, "Internal Server Error") }
            result["streams"] = streamResults
        }
        return .plist(result)
    }

    /// Derives the session key: FairPlay-decrypted ekey, hashed with the pairing secret.
    private func setupKeys(ekey: Data, eiv: Data) -> Bool {
        guard var key = fairPlay.decryptKey(ekey) else { return false }
        if let secret = pairing.sharedSecret {
            key = Data(Crypto.sha512(key, secret).prefix(16))
        }
        sessionKey = key
        audioIV = Data(eiv.prefix(16))
        return true
    }

    private func setupStreams(_ streams: [[String: Any]]) -> [[String: Any]]? {
        var results: [[String: Any]] = []
        for stream in streams {
            switch (stream["type"] as? NSNumber)?.intValue {
            case 110:
                let connectionID = (stream["streamConnectionID"] as? NSNumber)?.uint64Value ?? 0
                guard let port = startMirroring(streamConnectionID: connectionID) else { return nil }
                results.append(["type": 110, "dataPort": Int(port)])
            case 96:
                let ports = startAudio(stream)
                results.append(["type": 96, "dataPort": Int(ports.data), "controlPort": Int(ports.control)])
            default:
                break
            }
        }
        return results
    }

    private func identify(_ body: [String: Any]) {
        guard !started else { return }
        started = true
        let deviceID = body["deviceID"] as? String ?? remoteDescription
        let name = body["name"] as? String ?? "iPad"
        let model = body["model"] as? String ?? "iPad"
        log.info("Mirroring client \(name, privacy: .public) (\(model, privacy: .public))")
        frameSource = delegate?.sessionDidStart(self, deviceID: deviceID, name: name, model: model)
    }

    private func startMirroring(streamConnectionID: UInt64) -> UInt16? {
        guard let sessionKey else { return nil }
        mirrorListener?.close()
        let decoder = VideoDecoder { [weak self] pixelBuffer in
            self?.frameSource?.push(pixelBuffer)
            self?.reportSize(CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)))
        }
        self.decoder = decoder
        let parser = MirrorStreamParser(sessionKey: sessionKey, streamConnectionID: streamConnectionID) { [weak self] event in
            guard let self else { return }
            switch event {
            case let .parameterSets(sps, pps):
                decoder.configure(sps: sps, pps: pps)
            case let .frame(data):
                decoder.decode(data)
            case let .suspended(isSuspended):
                delegate?.session(self, suspended: isSuspended)
            }
        }
        mirrorParser = parser
        mirrorListener = TCPStreamListener(queue: queue, onData: { parser.append($0) }, onClose: {})
        return mirrorListener?.port
    }

    private func reportSize(_ size: CGSize) {
        queue.async {
            guard size != self.lastVideoSize else { return }
            self.lastVideoSize = size
            self.delegate?.session(self, videoSizeChanged: size)
        }
    }

    private func startAudio(_ stream: [String: Any]) -> (data: UInt16, control: UInt16) {
        audio?.stop()
        audio = nil
        guard configuration.audioEnabled, let sessionKey, let audioIV else { return (0, 0) }
        let compressionType = (stream["ct"] as? NSNumber)?.intValue ?? 8
        let samplesPerFrame = (stream["spf"] as? NSNumber)?.intValue ?? 480
        let receiver = AudioReceiver(queue: queue, key: sessionKey, iv: audioIV,
                                     compressionType: compressionType, samplesPerFrame: samplesPerFrame)
        receiver?.localVolume = localVolume
        audio = receiver
        return (receiver?.dataPort ?? 0, receiver?.controlPort ?? 0)
    }

    private func handleSetParameter(_ request: RTSPRequest) {
        guard request.header("Content-Type") == "text/parameters",
              let text = String(data: request.body, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\r\n") where line.hasPrefix("volume:") {
            guard let decibels = Float(line.dropFirst(7).trimmingCharacters(in: .whitespaces)) else { continue }
            // AirPlay volume: -30...0 dB, -144 = muted.
            let linear: Float = decibels <= -30 ? 0 : pow(10, decibels / 20)
            audio?.clientVolume = linear
            delegate?.session(self, volumeChanged: linear)
        }
    }

    private func handleTeardown(_ request: RTSPRequest) -> RTSPResponse {
        let types = (request.plistBody?["streams"] as? [[String: Any]])?
            .compactMap { ($0["type"] as? NSNumber)?.intValue } ?? []
        if types.contains(96) {
            audio?.stop()
            audio = nil
        }
        if types.contains(110) {
            stopMirroring()
        }
        var response = RTSPResponse.ok
        if types.isEmpty {
            response.disconnect = true
        }
        return response
    }

    private func stopMirroring() {
        mirrorListener?.close()
        mirrorListener = nil
        mirrorParser = nil
        decoder?.invalidate()
        decoder = nil
    }

    private func teardown() {
        guard !ended else { return }
        ended = true
        stopMirroring()
        audio?.stop()
        audio = nil
        timing?.close()
        timing = nil
        connection.cancel()
        delegate?.sessionDidEnd(self)
    }
}

// MARK: - Pairing and access control

extension AirPlaySession {
    private func handlePairVerify(_ request: RTSPRequest) -> RTSPResponse {
        guard let flag = request.body.first else { return .status(400, "Bad Request") }
        do {
            if flag == 1 {
                // With a code, only iPads paired before may skip it. An empty answer makes the iPad ask for
                // the code (pair-pin-start), as with UxPlay.
                if configuration.access.effectiveMode == .code, request.body.count == 68,
                   !configuration.access.isPaired(request.body.subdata(in: 36..<68)) {
                    return .ok
                }
                return .binary(try pairing.verifyStart(request.body))
            }
            try pairing.verifyFinish(request.body)
            return .binary(Data())
        } catch {
            log.error("pair-verify failed: \(error.localizedDescription, privacy: .public)")
            var response = RTSPResponse.status(470, "Connection Authorization Required")
            response.disconnect = true
            return response
        }
    }

    private func handlePairSetupPin(_ request: RTSPRequest) -> RTSPResponse {
        guard let body = request.plistBody else { return .status(400, "Bad Request") }
        let access = configuration.access
        switch pinPairing.handle(body, pin: access.currentCode, serverKey: configuration.identity.publicKey) {
        case let .reply(reply):
            return .plist(reply)
        case let .paired(reply, clientKey):
            access.pair(clientKey)
            return .plist(reply)
        case .failed:
            log.info("pair-setup-pin failed: wrong code or unexpected request")
            return .status(470, "Client Authentication Failure")
        }
    }
}
