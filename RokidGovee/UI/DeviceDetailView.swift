import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var vm: GoveeViewModel
    let device: GoveeDevice
    @Environment(\.dismiss) private var dismiss

    @State private var localBrightness: Double = 100
    @State private var localColorTemp:  Double = 4500
    @State private var isDraggingBri = false
    @State private var isDraggingTemp = false

    private var state: GoveeDeviceState? { vm.states[device.device] }
    private var isOn: Bool { state?.isOn ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    powerSection
                    if isOn {
                        if device.supportsBrightness  { brightnessSection }
                        if device.supportsColorTemp    { colorTempSection  }
                        if device.supportsColor        { colorSection      }
                    }
                    deviceInfoSection
                }
                .padding()
            }
            .navigationTitle(device.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { syncFromState() }
            .onChange(of: state?.brightness) { _, v in
                if !isDraggingBri, let v { localBrightness = Double(v) }
            }
            .onChange(of: state?.colorTemp) { _, v in
                if !isDraggingTemp, let v { localColorTemp = Double(v) }
            }
        }
    }

    // MARK: - Power section

    private var powerSection: some View {
        VStack(spacing: 16) {
            // Big power button
            Button {
                vm.toggle(device)
            } label: {
                ZStack {
                    Circle()
                        .fill(isOn
                              ? (state?.color?.color ?? Color.yellow).opacity(0.2)
                              : Color(.secondarySystemBackground))
                        .frame(width: 110, height: 110)
                    Circle()
                        .strokeBorder(isOn
                                      ? (state?.color?.color ?? Color.yellow)
                                      : Color.secondary.opacity(0.4),
                                      lineWidth: 3)
                        .frame(width: 110, height: 110)
                    Image(systemName: device.typeIcon)
                        .font(.system(size: 44))
                        .foregroundStyle(isOn
                                         ? (state?.color?.color ?? Color.yellow)
                                         : Color.secondary)
                }
            }
            .buttonStyle(.plain)

            Text(isOn ? "On" : "Off")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isOn ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Brightness section

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Brightness", systemImage: "sun.max.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            HStack {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(value: $localBrightness, in: 1...100, step: 1) {
                    EmptyView()
                } minimumValueLabel: { EmptyView() } maximumValueLabel: { EmptyView() }
                    .tint(.orange)
                    .simultaneousGesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in isDraggingBri = true }
                        .onEnded { _ in
                            isDraggingBri = false
                            vm.setBrightness(device, value: Int(localBrightness))
                        }
                    )
                Image(systemName: "sun.max")
                    .foregroundStyle(.orange)
            }

            Text("\(Int(localBrightness))%")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundStyle(.orange)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Color temp section

    private var colorTempSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Color Temperature", systemImage: "thermometer.medium")
                .font(.headline)

            HStack {
                Text("🕯️")
                Slider(value: $localColorTemp,
                       in: device.colorTempRange,
                       step: 100) {
                    EmptyView()
                } minimumValueLabel: { EmptyView() } maximumValueLabel: { EmptyView() }
                    .tint(colorTempGradientColor)
                    .simultaneousGesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in isDraggingTemp = true }
                        .onEnded { _ in
                            isDraggingTemp = false
                            vm.setColorTemp(device, kelvin: Int(localColorTemp))
                        }
                    )
                Text("❄️")
            }

            HStack {
                Text("Warm")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(localColorTemp))K")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(colorTempGradientColor)
                Spacer()
                Text("Cool")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var colorTempGradientColor: Color {
        let t = (localColorTemp - device.colorTempRange.lowerBound) /
                (device.colorTempRange.upperBound - device.colorTempRange.lowerBound)
        return Color(red: 1.0, green: 0.7 + 0.3 * t, blue: 0.4 + 0.6 * t)
    }

    // MARK: - Color presets section

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Color Presets", systemImage: "paintpalette.fill")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                      spacing: 10) {
                ForEach(ColorPreset.presets) { preset in
                    Button {
                        vm.setColor(device, preset: preset)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(preset.swiftUI)
                                .frame(width: 48, height: 48)
                            if let c = state?.color,
                               c.r == preset.r && c.g == preset.g && c.b == preset.b {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                                    .frame(width: 48, height: 48)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info

    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Device Info", systemImage: "info.circle")
                .font(.headline)
                .padding(.bottom, 4)
            infoRow("Model",  value: device.sku)
            infoRow("MAC",    value: device.device)
            infoRow("Type",   value: device.type.replacingOccurrences(of: "devices.types.", with: ""))
            infoRow("Capabilities", value: device.capabilities.map(\.instance).joined(separator: ", "))
            if let updated = vm.lastUpdated {
                infoRow("Last refreshed", value: updated.formatted(date: .omitted, time: .shortened))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Sync

    private func syncFromState() {
        if let bri = state?.brightness  { localBrightness = Double(bri) }
        if let temp = state?.colorTemp  { localColorTemp  = Double(temp) }
    }
}
