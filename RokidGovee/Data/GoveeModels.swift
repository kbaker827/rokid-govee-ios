import Foundation
import SwiftUI

// MARK: - Device list

struct GoveeDevice: Identifiable, Codable, Equatable {
    let sku:         String   // model / product code
    let device:      String   // MAC address — used as identifier in all API calls
    let deviceName:  String
    let type:        String
    let controllable: Bool
    let retrievable:  Bool
    let capabilities: [GoveeCapability]

    var id: String { device }

    var displayName: String {
        deviceName.isEmpty ? "\(sku) (\(device.suffix(5)))" : deviceName
    }

    // Derived capability flags
    var supportsColor:     Bool { capabilities.contains { $0.type == "devices.capabilities.color_setting" } }
    var supportsColorTemp: Bool { capabilities.contains { $0.type == "devices.capabilities.color_temp"    } }
    var supportsBrightness: Bool { capabilities.contains { $0.type == "devices.capabilities.range" && $0.instance == "brightness" } }

    var colorTempRange: ClosedRange<Double> {
        if let cap = capabilities.first(where: { $0.type == "devices.capabilities.color_temp" }),
           let range = cap.parameters?.range, range.count >= 2 {
            return Double(range[0])...Double(range[1])
        }
        return 2000...9000
    }

    var typeIcon: String {
        let s = sku.uppercased()
        if s.hasPrefix("H60") { return "lightbulb.fill" }
        if s.hasPrefix("H61") { return "light.strip.rightthird.filled" }
        if s.hasPrefix("H70") { return "lamp.floor.fill" }
        if s.hasPrefix("H50") { return "lamp.desk.fill" }
        if s.hasPrefix("H80") { return "light.beacon.max.fill" }
        if s.hasPrefix("H71") { return "light.cylindrical.ceiling.fill" }
        if type.contains("plug") { return "powerplug.fill" }
        return "lightbulb.fill"
    }
}

struct GoveeCapability: Codable, Equatable {
    let type:       String
    let instance:   String
    let parameters: CapabilityParameters?
}

struct CapabilityParameters: Codable, Equatable {
    let range:      [Int]?
    let colorModel: String?
}

// MARK: - Device state

struct GoveeDeviceState: Equatable {
    let device: String
    let sku:    String
    var isOnline:   Bool   = false
    var isOn:       Bool   = false
    var brightness: Int    = 100     // 0-100
    var color:      GoveeColor?
    var colorTemp:  Int?             // Kelvin

    var compactLine: String {
        guard isOn else { return "off" }
        var parts = ["ON", "bri:\(brightness)%"]
        if let c = color      { parts.append(c.hex) }
        if let t = colorTemp  { parts.append("\(t)K") }
        return parts.joined(separator: " · ")
    }

    var statusEmoji: String { isOn ? "💡" : "○" }
}

struct GoveeColor: Equatable, Codable {
    let r: Int
    let g: Int
    let b: Int

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    var color: Color { Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255) }
}

// MARK: - API response shapes

struct GoveeListResponse: Codable {
    let code: Int
    let message: String
    let data: GoveeListData?
}
struct GoveeListData: Codable {
    let devices: [GoveeDevice]
}

struct GoveeStateRequestBody: Codable {
    let requestId: String
    let payload: StatePayload

    struct StatePayload: Codable {
        let sku: String
        let device: String
    }
}

struct GoveeStateResponse: Codable {
    let code: Int
    let message: String
    let data: GoveeStateData?
}
struct GoveeStateData: Codable {
    let device: String
    let model: String?
    let sku: String?
    let properties: [GoveeRawProperty]
}

/// Each element of the `properties` array is a single-key dict:
///   {"powerSwitch":1}, {"brightness":80}, {"color":{"r":…}}, {"colorTem":4500}, {"online":true}
struct GoveeRawProperty: Codable {
    let powerSwitch: Int?
    let brightness:  Int?
    let color:       GoveeColor?
    let colorTem:    Int?
    let online:      Bool?

    enum CodingKeys: String, CodingKey {
        case powerSwitch, brightness, color, colorTem, online
    }
}

extension GoveeDeviceState {
    init(device: String, sku: String, properties: [GoveeRawProperty]) {
        self.device = device
        self.sku    = sku
        for p in properties {
            if let v = p.online      { isOnline   = v }
            if let v = p.powerSwitch { isOn       = v == 1 }
            if let v = p.brightness  { brightness = v }
            if let v = p.color       { color      = v }
            if let v = p.colorTem    { colorTemp  = v }
        }
    }
}

// MARK: - Control request

struct GoveeControlRequest: Codable {
    let requestId: String
    let payload: ControlPayload

    struct ControlPayload: Codable {
        let sku: String
        let device: String
        let capability: GoveeCapabilityCommand
    }
}

struct GoveeCapabilityCommand: Codable {
    let type:     String
    let instance: String
    let value:    GoveeCommandValue
}

enum GoveeCommandValue: Codable {
    case int(Int)
    case color(GoveeColor)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i   = try? c.decode(Int.self)       { self = .int(i);    return }
        if let col = try? c.decode(GoveeColor.self) { self = .color(col); return }
        throw DecodingError.typeMismatch(GoveeCommandValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected Int or Color"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i):    try c.encode(i)
        case .color(let col): try c.encode(col)
        }
    }
}

// MARK: - Glasses format

enum GlassesFormat: String, CaseIterable, Identifiable {
    case summary    = "summary"
    case deviceList = "deviceList"
    case minimal    = "minimal"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .summary:    return "Summary"
        case .deviceList: return "Device List"
        case .minimal:    return "Minimal"
        }
    }
    var description: String {
        switch self {
        case .summary:    return "X/Y on, lists active device names"
        case .deviceList: return "Every device with on/off state and brightness"
        case .minimal:    return "Single line: X of Y lights on"
        }
    }
}

// MARK: - Error

enum GoveeError: LocalizedError {
    case missingAPIKey
    case apiError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:             return "No Govee API key — add one in Settings."
        case .apiError(let c, let m):    return "Govee API \(c): \(m)"
        case .decodingError(let detail): return "Govee decode error: \(detail)"
        }
    }
}

// MARK: - Preset colours

struct ColorPreset: Identifiable {
    let id = UUID()
    let name: String
    let r: Int; let g: Int; let b: Int
    var goveeColor: GoveeColor { GoveeColor(r: r, g: g, b: b) }
    var swiftUI: Color { Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255) }
}

extension ColorPreset {
    static let presets: [ColorPreset] = [
        .init(name: "Warm White", r: 255, g: 220, b: 160),
        .init(name: "Cool White", r: 220, g: 230, b: 255),
        .init(name: "Red",        r: 255, g:   0, b:   0),
        .init(name: "Orange",     r: 255, g: 120, b:   0),
        .init(name: "Yellow",     r: 255, g: 220, b:   0),
        .init(name: "Green",      r:   0, g: 220, b:  60),
        .init(name: "Cyan",       r:   0, g: 220, b: 255),
        .init(name: "Blue",       r:  30, g:  80, b: 255),
        .init(name: "Purple",     r: 160, g:   0, b: 255),
        .init(name: "Pink",       r: 255, g:  60, b: 180),
    ]
}
