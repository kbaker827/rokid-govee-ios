import SwiftUI
import Network

struct SettingsView: View {
    @EnvironmentObject private var vm: GoveeViewModel
    @State private var showAPIKey = false
    @State private var localIP:   String = "—"

    var body: some View {
        NavigationStack {
            Form {

                // MARK: API Key
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("Paste API key here", text: Binding(
                                get:  { vm.apiKey },
                                set:  { vm.setAPIKey($0) }
                            ))
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Govee API key", text: Binding(
                                get:  { vm.apiKey },
                                set:  { vm.setAPIKey($0) }
                            ))
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to get your API key:")
                            .font(.caption.weight(.semibold))
                        Text("1. Open Govee Home app\n2. Settings → About → Apply for API Key\n3. Key arrives by email within minutes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } header: {
                    Label("Govee API Key", systemImage: "key.fill")
                }

                // MARK: Connection
                Section("Connection") {
                    LabeledContent("iPhone IP", value: localIP)
                    LabeledContent("Glasses port", value: ":8103")
                        .foregroundStyle(.secondary)

                    HStack {
                        Circle()
                            .fill(vm.glassesServer.isRunning ? .cyan : .red)
                            .frame(width: 8, height: 8)
                        Text(vm.isGlassesWatching
                             ? "\(vm.glassesServer.clientCount) glasses connected"
                             : "Waiting for glasses on :8103")
                            .foregroundStyle(vm.isGlassesWatching ? .cyan : .secondary)
                    }

                    if let updated = vm.lastUpdated {
                        LabeledContent("Last refresh",
                                       value: updated.formatted(date: .omitted, time: .shortened))
                    }
                    LabeledContent("Devices", value: "\(vm.totalCount) total · \(vm.onCount) on")
                }

                // MARK: Polling
                Section {
                    Picker("Poll every", selection: Binding(
                        get:  { vm.pollInterval },
                        set:  { vm.setPollInterval($0) }
                    )) {
                        Text("15 s").tag(15)
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                        Text("2 min").tag(120)
                        Text("5 min").tag(300)
                    }
                    Button("Refresh Now") {
                        Task { await vm.refresh() }
                    }
                    .disabled(vm.isLoading || vm.apiKey.isEmpty)
                } header: {
                    Text("Auto-Refresh")
                } footer: {
                    Text("Govee allows ~10 requests/min per device. 30 s is safe for up to 5 devices.")
                }

                // MARK: Glasses Display
                Section {
                    Toggle("Stream to glasses", isOn: Binding(
                        get:  { vm.streamToGlasses },
                        set:  { vm.setStreamToGlasses($0) }
                    ))

                    Picker("Display format", selection: Binding(
                        get:  { vm.glassesFormat },
                        set:  { vm.setGlassesFormat($0) }
                    )) {
                        ForEach(GlassesFormat.allCases) { fmt in
                            VStack(alignment: .leading) {
                                Text(fmt.displayName)
                                Text(fmt.description).font(.caption).foregroundStyle(.secondary)
                            }.tag(fmt)
                        }
                    }
                } header: {
                    Text("Glasses Display")
                }

                // MARK: Glasses commands
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        commandRow("all on",            "Turn all devices on")
                        commandRow("all off",           "Turn all devices off")
                        commandRow("brightness 50",     "Set all to 50%")
                        commandRow("<name> on",         "Turn one device on")
                        commandRow("<name> off",        "Turn one device off")
                        commandRow("<name> brightness N","Set one device to N%")
                        commandRow("refresh",           "Fetch latest states")
                        commandRow("summary",           "Show overview on glasses")
                    }
                } header: {
                    Text("Glasses Voice / Text Commands")
                } footer: {
                    Text("Send {\"type\":\"cmd\",\"text\":\"<command>\"} from the glasses over TCP :8103.")
                }

                // MARK: About
                Section("About") {
                    LabeledContent("App",      value: "Rokid Govee HUD")
                    LabeledContent("Protocol", value: "Govee OpenAPI v1 + TCP :8103")
                    LabeledContent("Version",  value: "1.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear { localIP = getLocalIP() ?? "Check Wi-Fi" }
        }
    }

    private func commandRow(_ cmd: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(cmd)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.cyan)
                .frame(width: 160, alignment: .leading)
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
               ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr,
                               socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return address
    }
}
