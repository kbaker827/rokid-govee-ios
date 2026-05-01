import Foundation
import Network

/// TCP server on :8103 — broadcasts Govee device state to Rokid glasses
/// and receives control commands from glasses.
///
/// Inbound from glasses (JSON, newline-delimited):
///   {"type":"cmd","text":"all on"}
///   {"type":"cmd","text":"lights off"}
///   {"type":"cmd","text":"brightness 50"}
///   {"type":"cmd","text":"<device name> on"}
///   {"type":"cmd","text":"refresh"}
@MainActor
final class GlassesServer: ObservableObject {

    @Published var isRunning   = false
    @Published var clientCount = 0

    /// Called when glasses send a command string.
    var onGlassesCommand: ((String) -> Void)?

    private var listener:    NWListener?
    private var connections: [GlassesConn] = []
    private let port: NWEndpoint.Port = 8103
    private let queue = DispatchQueue(label: "GoveeGlassesQ", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.isRunning = (state == .ready) }
        }
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.conn.cancel() }
        connections.removeAll()
        clientCount = 0; isRunning = false
    }

    // MARK: - Broadcast helpers

    /// Full device summary according to chosen format.
    func broadcastDevices(_ devices: [GoveeDevice],
                          states: [String: GoveeDeviceState],
                          format: GlassesFormat) {
        send(type: "devices", text: buildSummary(devices: devices, states: states, format: format))
    }

    /// Alert when a device flips state.
    func broadcastDeviceChange(_ device: GoveeDevice, state: GoveeDeviceState) {
        let text = "\(state.statusEmoji) \(device.displayName): \(state.compactLine)"
        send(type: "device_change", text: text)
    }

    /// Acknowledgement after a control command.
    func broadcastControl(_ deviceName: String, action: String) {
        send(type: "control", text: "⚙️ \(deviceName): \(action)")
    }

    func broadcastError(_ msg: String)   { send(type: "error",  text: "⚠️ \(msg)") }
    func broadcastStatus(_ msg: String)  { send(type: "status", text: msg) }

    // MARK: - Private

    private func buildSummary(devices: [GoveeDevice],
                              states: [String: GoveeDeviceState],
                              format: GlassesFormat) -> String {
        let total   = devices.count
        let onCount = states.values.filter(\.isOn).count

        switch format {
        case .minimal:
            return "\(onCount)/\(total) lights on"

        case .summary:
            var lines = ["\(onCount)/\(total) lights on"]
            let onDevices = devices.filter { states[$0.device]?.isOn == true }
            if !onDevices.isEmpty {
                lines.append("On: " + onDevices.prefix(3).map(\.displayName).joined(separator: ", "))
            }
            return lines.joined(separator: "\n")

        case .deviceList:
            return devices.prefix(8).map { dev in
                let st  = states[dev.device]
                let icon = st?.isOn == true ? "💡" : "○"
                let bri  = st?.isOn == true ? " \(st?.brightness ?? 100)%" : ""
                return "\(icon) \(dev.displayName)\(bri)"
            }.joined(separator: "\n")
        }
    }

    private func send(type: String, text: String) {
        let dict: [String: String] = ["type": type, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        let packet = data + Data([0x0A])
        connections.forEach { $0.conn.send(content: packet, completion: .contentProcessed { _ in }) }
    }

    private func accept(_ conn: NWConnection) {
        let wrapper = GlassesConn(conn: conn)
        conn.stateUpdateHandler = { [weak self, weak wrapper] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor [weak self, weak wrapper] in
                    guard let wrapper else { return }
                    self?.connections.removeAll { $0 === wrapper }
                    self?.clientCount = self?.connections.count ?? 0
                }
            default: break
            }
        }
        conn.start(queue: queue)
        connections.append(wrapper)
        clientCount = connections.count
        send(type: "status", text: "Rokid Govee HUD — say a command or wait for update")
        receiveNext(wrapper)
    }

    private func receiveNext(_ wrapper: GlassesConn) {
        wrapper.conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak wrapper] data, _, done, err in
            Task { @MainActor [weak self, weak wrapper] in
                guard let self, let wrapper else { return }
                if let d = data, !d.isEmpty {
                    wrapper.buffer.append(d)
                    self.flush(wrapper)
                }
                if !done && err == nil { self.receiveNext(wrapper) }
            }
        }
    }

    private func flush(_ wrapper: GlassesConn) {
        while let idx = wrapper.buffer.firstIndex(of: 0x0A) {
            let lineData = wrapper.buffer[wrapper.buffer.startIndex..<idx]
            wrapper.buffer.removeSubrange(wrapper.buffer.startIndex...idx)
            guard let raw  = String(data: lineData, encoding: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: String],
                  json["type"] == "cmd",
                  let text = json["text"], !text.isEmpty else { continue }
            onGlassesCommand?(text)
        }
    }
}

private final class GlassesConn {
    let conn: NWConnection
    var buffer = Data()
    init(conn: NWConnection) { self.conn = conn }
}
