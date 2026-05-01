import SwiftUI

struct DeviceListView: View {
    @EnvironmentObject private var vm: GoveeViewModel
    @State private var selectedDevice: GoveeDevice?
    @State private var showAPIKeyPrompt = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.apiKey.isEmpty {
                    noKeyPlaceholder
                } else if vm.devices.isEmpty && !vm.isLoading {
                    emptyPlaceholder
                } else {
                    deviceList
                }
            }
            .navigationTitle("Govee Devices")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading)  { statusBadge }
                ToolbarItem(placement: .navigationBarTrailing) { refreshButton }
            }
            .sheet(item: $selectedDevice) { device in
                DeviceDetailView(device: device)
                    .environmentObject(vm)
            }
            .refreshable { await vm.refresh() }
        }
    }

    // MARK: - Summary header

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            // On/off stat
            VStack(spacing: 2) {
                Text("\(vm.onCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
                Text("on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 44)

            VStack(spacing: 2) {
                Text("\(vm.totalCount - vm.onCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("off")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 44)

            VStack(spacing: 2) {
                Text("\(vm.totalCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("total")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - All-on / all-off buttons

    private var globalControls: some View {
        HStack(spacing: 12) {
            Button {
                vm.turnAllOn()
            } label: {
                Label("All On", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)

            Button {
                vm.turnAllOff()
            } label: {
                Label("All Off", systemImage: "lightbulb.slash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Device list

    private var deviceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                summaryHeader
                    .padding(.bottom, 4)
                globalControls
                    .padding(.bottom, 8)

                if let err = vm.errorMessage {
                    errorBanner(err)
                }

                ForEach(vm.devices) { device in
                    DeviceRow(device: device)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDevice = device }
                    Divider().padding(.leading, 60)
                }
            }
        }
    }

    // MARK: - Placeholders

    private var noKeyPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow.opacity(0.8))
            Text("Add your Govee API key")
                .font(.title2.weight(.semibold))
            Text("Go to Settings → paste your API key from\nthe Govee Home app → Settings → About.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                // Handled by tab switch in ContentView
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
        }
        .padding(40)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No devices found")
                .font(.title3.weight(.medium))
            Text("Make sure your Govee lights are on the same\nWi-Fi and your API key is correct.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(msg)
                .font(.footnote)
                .foregroundStyle(.red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Toolbar items

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(vm.glassesServer.isRunning ? .cyan : Color(white: 0.4))
                .frame(width: 7, height: 7)
            Text("\(vm.glassesServer.clientCount) glasses")
                .font(.caption)
                .foregroundStyle(.cyan.opacity(vm.glassesServer.isRunning ? 1 : 0.5))
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await vm.refresh() }
        } label: {
            if vm.isLoading {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(vm.isLoading)
    }
}

// MARK: - Device row

struct DeviceRow: View {
    @EnvironmentObject private var vm: GoveeViewModel
    let device: GoveeDevice

    private var state: GoveeDeviceState? { vm.states[device.device] }

    var body: some View {
        HStack(spacing: 14) {
            // Icon with color glow when on
            ZStack {
                if state?.isOn == true {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                }
                Image(systemName: device.typeIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(state?.isOn == true ? iconColor : .secondary)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(state?.compactLine ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Brightness badge
            if state?.isOn == true, let bri = state?.brightness {
                Text("\(bri)%")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            // Power toggle
            Toggle("", isOn: Binding(
                get: { state?.isOn ?? false },
                set: { _ in vm.toggle(device) }
            ))
            .labelsHidden()
            .tint(.yellow)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        if let c = state?.color { return c.color }
        return .yellow
    }
}
