import Foundation

/// All Govee API calls.  Runs on its own actor to protect shared state.
actor GoveeAPIClient {

    private let base = "https://openapi.api.govee.com/router/api/v1"
    private var apiKey: String

    init(apiKey: String = "") { self.apiKey = apiKey }

    func setAPIKey(_ key: String) { apiKey = key }

    // MARK: - Devices list

    func fetchDevices() async throws -> [GoveeDevice] {
        let data = try await get("/user/devices")
        do {
            let resp = try JSONDecoder().decode(GoveeListResponse.self, from: data)
            guard resp.code == 200, let devices = resp.data?.devices else {
                throw GoveeError.apiError(resp.code, resp.message)
            }
            return devices
        } catch let e as GoveeError { throw e }
        catch { throw GoveeError.decodingError(error.localizedDescription) }
    }

    // MARK: - Device state

    func fetchDeviceState(sku: String, device: String) async throws -> GoveeDeviceState {
        let body = GoveeStateRequestBody(
            requestId: UUID().uuidString,
            payload: .init(sku: sku, device: device)
        )
        let data = try await post("/device/state", body: body)
        do {
            let resp = try JSONDecoder().decode(GoveeStateResponse.self, from: data)
            guard resp.code == 200, let stateData = resp.data else {
                throw GoveeError.apiError(resp.code, resp.message)
            }
            return GoveeDeviceState(device: device,
                                    sku: stateData.sku ?? stateData.model ?? sku,
                                    properties: stateData.properties)
        } catch let e as GoveeError { throw e }
        catch { throw GoveeError.decodingError(error.localizedDescription) }
    }

    // MARK: - Control

    func turn(_ device: GoveeDevice, on: Bool) async throws {
        try await control(device,
            capability: .init(
                type: "devices.capabilities.on_off",
                instance: "powerSwitch",
                value: .int(on ? 1 : 0)
            )
        )
    }

    func setBrightness(_ device: GoveeDevice, value: Int) async throws {
        try await control(device,
            capability: .init(
                type: "devices.capabilities.range",
                instance: "brightness",
                value: .int(min(100, max(0, value)))
            )
        )
    }

    func setColor(_ device: GoveeDevice, r: Int, g: Int, b: Int) async throws {
        try await control(device,
            capability: .init(
                type: "devices.capabilities.color_setting",
                instance: "color",
                value: .color(GoveeColor(r: r, g: g, b: b))
            )
        )
    }

    func setColorTemp(_ device: GoveeDevice, kelvin: Int) async throws {
        try await control(device,
            capability: .init(
                type: "devices.capabilities.color_temp",
                instance: "colorTem",
                value: .int(kelvin)
            )
        )
    }

    // MARK: - Private

    private func control(_ device: GoveeDevice, capability: GoveeCapabilityCommand) async throws {
        let body = GoveeControlRequest(
            requestId: UUID().uuidString,
            payload: .init(sku: device.sku, device: device.device, capability: capability)
        )
        _ = try await post("/device/control", body: body)
    }

    private func get(_ path: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw GoveeError.missingAPIKey }
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(apiKey,             forHTTPHeaderField: "Govee-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data: data)
        return data
    }

    private func post<T: Encodable>(_ path: String, body: T) async throws -> Data {
        guard !apiKey.isEmpty else { throw GoveeError.missingAPIKey }
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey,             forHTTPHeaderField: "Govee-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data: data)
        return data
    }

    private func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoveeError.apiError(http.statusCode, msg)
        }
    }
}
