import Foundation
import Network
import Observation
import os

/// Owns the AirPlay listener and the list of connected devices.
@MainActor
@Observable
final class Receiver {
    enum Status: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    private(set) var devices: [MirroredDevice] = []
    private(set) var status: Status = .stopped

    var visibleDevices: [MirroredDevice] { devices.filter { !$0.isHidden } }

    var statusDescription: String {
        switch status {
        case .running:
            let count = devices.count
            return count == 0 ? "„\(settings.receiverName)“ bereit" : "\(count) Gerät\(count == 1 ? "" : "e") verbunden"
        case .starting: return "Startet …"
        case .stopped: return "Gestoppt"
        case let .failed(message): return "Fehler: \(message)"
        }
    }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let bonjour = BonjourAdvertiser()
    @ObservationIgnored private var sessions: [UUID: AirPlaySession] = [:]
    @ObservationIgnored private var devicesBySession: [UUID: MirroredDevice] = [:]
    @ObservationIgnored private let identity = ServerIdentity.loadOrCreate()
    @ObservationIgnored private let bridge = SessionBridge()
    @ObservationIgnored private let log = Logger(subsystem: "Totalreflexion", category: "Receiver")
    @ObservationIgnored private var configuration: ReceiverConfiguration?

    let settings: AppSettings
    let deviceSettings: DeviceSettingsStore

    init(settings: AppSettings, deviceSettings: DeviceSettingsStore) {
        self.settings = settings
        self.deviceSettings = deviceSettings
        bridge.receiver = self
    }

    func start() {
        stop()
        status = .starting
        configuration = ReceiverConfiguration(
            name: settings.receiverName, identity: identity,
            width: settings.resolution.size.width, height: settings.resolution.size.height,
            maxFPS: settings.maxFPS, audioEnabled: settings.audioEnabled)
        // macOS' own AirPlay receiver occupies 7000, so try a nearby fixed port first.
        startListener(preferredPorts: [7100, 7200, 0])
    }

    func restart() {
        start()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        bonjour.stop()
        for session in sessions.values {
            session.stop()
        }
        status = .stopped
    }

    private func startListener(preferredPorts: [UInt16]) {
        guard let portNumber = preferredPorts.first else {
            status = .failed("Kein freier Netzwerk-Port gefunden.")
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let port = portNumber == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: portNumber)!
        guard let listener = try? NWListener(using: parameters, on: port) else {
            startListener(preferredPorts: Array(preferredPorts.dropFirst()))
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.listenerStateChanged(state, listener: listener, remaining: preferredPorts) }
        }
        listener.start(queue: .main)
    }

    private func listenerStateChanged(_ state: NWListener.State, listener: NWListener, remaining: [UInt16]) {
        guard listener === self.listener else { return }
        switch state {
        case .ready:
            guard let port = listener.port?.rawValue else { return }
            bonjour.start(name: settings.receiverName, port: port, identity: identity)
            status = .running(port: port)
        case let .failed(error):
            log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
            listener.cancel()
            self.listener = nil
            if remaining.count > 1 {
                startListener(preferredPorts: Array(remaining.dropFirst()))
            } else {
                status = .failed(error.localizedDescription)
            }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard let configuration else {
            connection.cancel()
            return
        }
        let session = AirPlaySession(connection: connection, configuration: configuration)
        session.delegate = bridge
        sessions[session.id] = session
        session.start()
    }

    // MARK: - Session events (main actor)

    fileprivate func sessionStarted(_ session: AirPlaySession, device: MirroredDevice) {
        guard sessions[session.id] != nil else { return }
        device.disconnect = { [weak session] in session?.stop() }
        device.volumeChanged = { [weak session] volume in session?.setLocalVolume(volume) }
        devicesBySession[session.id] = device
        // A reconnecting iPad replaces its stale entry.
        devices.removeAll { $0.clientDeviceID == device.clientDeviceID }
        devices.append(device)
        let muted = deviceSettings[device].muted
        session.setLocalVolume(muted ? 0 : 1)
    }

    fileprivate func sessionEnded(_ session: AirPlaySession) {
        sessions[session.id] = nil
        if let device = devicesBySession.removeValue(forKey: session.id) {
            devices.removeAll { $0 === device }
        }
    }

    fileprivate func device(for session: AirPlaySession) -> MirroredDevice? {
        devicesBySession[session.id]
    }
}

/// Receives session callbacks on session queues and forwards them to the main actor.
private final class SessionBridge: AirPlaySessionDelegate, @unchecked Sendable {
    weak var receiver: Receiver?

    func sessionDidStart(_ session: AirPlaySession, deviceID: String, name: String, model: String) -> FrameSource {
        let frames = FrameSource()
        let address = session.remoteDescription
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                let device = MirroredDevice(clientDeviceID: deviceID, reportedName: name, model: model,
                                            address: address, frames: frames)
                self?.receiver?.sessionStarted(session, device: device)
            }
        }
        return frames
    }

    func session(_ session: AirPlaySession, videoSizeChanged size: CGSize) {
        onMain(session) { device in
            device.videoSize = size
            device.hasVideo = true
        }
    }

    func session(_ session: AirPlaySession, suspended: Bool) {
        onMain(session) { $0.isSuspended = suspended }
    }

    func session(_ session: AirPlaySession, volumeChanged volume: Float) {
        onMain(session) { $0.clientVolume = volume }
    }

    func sessionDidEnd(_ session: AirPlaySession) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.receiver?.sessionEnded(session) }
        }
    }

    private func onMain(_ session: AirPlaySession, _ change: @escaping @MainActor (MirroredDevice) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                if let device = self?.receiver?.device(for: session) {
                    change(device)
                }
            }
        }
    }
}
