import Foundation
import Combine

@MainActor
final class GoveeViewModel: ObservableObject {

    // MARK: - Published state
    @Published var devices:         [GoveeDevice]              = []
    @Published var states:          [String: GoveeDeviceState] = [:]
    @Published var isLoading:       Bool                       = false
    @Published var lastUpdated:     Date?
    @Published var errorMessage:    String?
    @Published var glassesFormat:   GlassesFormat              = .summary
    @Published var streamToGlasses: Bool                       = true
    @Published var pollInterval:    Int                        = 30
    @Published var apiKey:          String                     = ""

    // MARK: - Services
    let glassesServer = GlassesServer()
    private let api   = GoveeAPIClient()

    // MARK: - Computed
    var isGlassesWatching: Bool { glassesServer.clientCount > 0 }
    var onCount:    Int { states.values.filter(\.isOn).count }
    var totalCount: Int { devices.count }
    var offlineCount: Int { states.values.filter { !$0.isOnline }.count }

    // MARK: - Private
    private var pollTask:    Task<Void, Never>?
    private var prevStates:  [String: GoveeDeviceState] = [:]

    // MARK: - Init

    init() {
        loadSettings()
        glassesServer.onGlassesCommand = { [weak self] text in
            Task { @MainActor [weak self] in await self?.handleGlassesCommand(text) }
        }
        glassesServer.start()
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startPolling()
        }
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = await self?.pollInterval else { break }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    // MARK: - Refresh

    func refresh() async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "No API key — add one in Settings"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            // 1. Fetch device list
            let fetched = try await api.fetchDevices()
            devices = fetched

            // 2. Fetch state for each retrievable device (200 ms gap to respect rate limits)
            var newStates: [String: GoveeDeviceState] = [:]
            for dev in fetched where dev.retrievable {
                if Task.isCancelled { break }
                if let state = try? await api.fetchDeviceState(sku: dev.sku, device: dev.device) {
                    newStates[dev.device] = state
                }
                try? await Task.sleep(for: .milliseconds(200))
            }

            prevStates = states
            states     = newStates
            lastUpdated = Date()
            checkStateChanges()
            broadcastToGlasses()
        } catch {
            errorMessage = error.localizedDescription
            glassesServer.broadcastError(error.localizedDescription)
        }
        isLoading = false
    }

    // MARK: - Device control (public)

    func toggle(_ device: GoveeDevice) {
        let on = states[device.device]?.isOn ?? false
        Task { await doControl(device, action: on ? .turnOff : .turnOn) }
    }

    func setBrightness(_ device: GoveeDevice, value: Int) {
        Task { await doControl(device, action: .brightness(value)) }
    }

    func setColor(_ device: GoveeDevice, preset: ColorPreset) {
        Task { await doControl(device, action: .color(r: preset.r, g: preset.g, b: preset.b)) }
    }

    func setColorTemp(_ device: GoveeDevice, kelvin: Int) {
        Task { await doControl(device, action: .colorTemp(kelvin)) }
    }

    func turnAllOn()  { devices.forEach { d in Task { await doControl(d, action: .turnOn)  } } }
    func turnAllOff() { devices.forEach { d in Task { await doControl(d, action: .turnOff) } } }

    func setAllBrightness(_ v: Int) {
        devices.filter(\.supportsBrightness).forEach { d in
            Task { await doControl(d, action: .brightness(v)) }
        }
    }

    // MARK: - Private control

    private enum ControlAction {
        case turnOn, turnOff
        case brightness(Int)
        case color(r: Int, g: Int, b: Int)
        case colorTemp(Int)
    }

    private func doControl(_ device: GoveeDevice, action: ControlAction) async {
        do {
            switch action {
            case .turnOn:
                try await api.turn(device, on: true)
                patchState(device.device) { $0.isOn = true }
                glassesServer.broadcastControl(device.displayName, action: "on")

            case .turnOff:
                try await api.turn(device, on: false)
                patchState(device.device) { $0.isOn = false }
                glassesServer.broadcastControl(device.displayName, action: "off")

            case .brightness(let v):
                try await api.setBrightness(device, value: v)
                patchState(device.device) { $0.brightness = v }
                glassesServer.broadcastControl(device.displayName, action: "brightness \(v)%")

            case .color(let r, let g, let b):
                try await api.setColor(device, r: r, g: g, b: b)
                patchState(device.device) { $0.color = GoveeColor(r: r, g: g, b: b) }
                glassesServer.broadcastControl(device.displayName,
                                               action: "color \(GoveeColor(r:r,g:g,b:b).hex)")

            case .colorTemp(let k):
                try await api.setColorTemp(device, kelvin: k)
                patchState(device.device) { $0.colorTemp = k }
                glassesServer.broadcastControl(device.displayName, action: "\(k)K")
            }
        } catch {
            errorMessage = error.localizedDescription
            glassesServer.broadcastError(error.localizedDescription)
        }
    }

    private func patchState(_ id: String, mutation: (inout GoveeDeviceState) -> Void) {
        if var s = states[id] { mutation(&s); states[id] = s }
    }

    // MARK: - Glasses broadcast

    private func broadcastToGlasses() {
        guard streamToGlasses, glassesServer.clientCount > 0 else { return }
        glassesServer.broadcastDevices(devices, states: states, format: glassesFormat)
    }

    private func checkStateChanges() {
        for dev in devices {
            guard let n = states[dev.device], let o = prevStates[dev.device] else { continue }
            if n.isOn != o.isOn || n.brightness != o.brightness {
                glassesServer.broadcastDeviceChange(dev, state: n)
            }
        }
    }

    // MARK: - Glasses commands

    private func handleGlassesCommand(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        // Global on/off
        if lower == "all on"  || lower == "lights on"  { turnAllOn();  return }
        if lower == "all off" || lower == "lights off" { turnAllOff(); return }

        // Refresh / summary
        if lower == "refresh" { await refresh(); return }
        if lower == "status" || lower == "summary" {
            glassesServer.broadcastDevices(devices, states: states, format: glassesFormat)
            return
        }

        // "brightness N" / "dim N"
        for prefix in ["brightness ", "dim ", "set brightness "] {
            if lower.hasPrefix(prefix),
               let v = Int(lower.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)) {
                setAllBrightness(v)
                glassesServer.broadcastStatus("All → brightness \(v)%")
                return
            }
        }

        // "<device name> on/off/brightness N"
        for dev in devices {
            let name = dev.displayName.lowercased()
            if lower.hasPrefix(name) {
                let rest = lower.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                if rest == "on"  { Task { await doControl(dev, action: .turnOn)  }; return }
                if rest == "off" { Task { await doControl(dev, action: .turnOff) }; return }
                if rest.hasPrefix("brightness "),
                   let v = Int(rest.dropFirst("brightness ".count).trimmingCharacters(in: .whitespaces)) {
                    Task { await doControl(dev, action: .brightness(v)) }
                    return
                }
            }
        }

        glassesServer.broadcastStatus("Unknown: \(text)")
    }

    // MARK: - Settings

    func setAPIKey(_ key: String) {
        apiKey = key
        UserDefaults.standard.set(key, forKey: "govee_api_key")
        Task { await api.setAPIKey(key) }
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startPolling()
        } else {
            stopPolling()
        }
    }

    func setGlassesFormat(_ fmt: GlassesFormat) {
        glassesFormat = fmt
        UserDefaults.standard.set(fmt.rawValue, forKey: "govee_glasses_format")
    }

    func setStreamToGlasses(_ val: Bool) {
        streamToGlasses = val
        UserDefaults.standard.set(val, forKey: "govee_stream_glasses")
        if !val { glassesServer.broadcastStatus("Streaming paused") }
    }

    func setPollInterval(_ val: Int) {
        pollInterval = val
        UserDefaults.standard.set(val, forKey: "govee_poll_interval")
        if !apiKey.isEmpty { startPolling() }
    }

    private func loadSettings() {
        let ud = UserDefaults.standard
        apiKey = ud.string(forKey: "govee_api_key") ?? ""
        streamToGlasses = ud.object(forKey: "govee_stream_glasses") as? Bool ?? true
        if let raw = ud.string(forKey: "govee_glasses_format"),
           let fmt = GlassesFormat(rawValue: raw) { glassesFormat = fmt }
        let pi = ud.integer(forKey: "govee_poll_interval")
        pollInterval = pi > 0 ? pi : 30
        Task { await api.setAPIKey(apiKey) }
    }
}
