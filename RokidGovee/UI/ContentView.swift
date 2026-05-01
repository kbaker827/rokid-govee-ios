import SwiftUI

struct ContentView: View {
    @StateObject private var vm = GoveeViewModel()

    var body: some View {
        TabView {
            DeviceListView()
                .tabItem { Label("Devices", systemImage: "lightbulb.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(vm)
        .tint(.yellow)
    }
}
