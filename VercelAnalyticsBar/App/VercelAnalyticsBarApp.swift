import AppKit
import SwiftUI
import VercelAnalyticsCore

@main
struct VercelAnalyticsBarApp: App {
    var body: some Scene {
        MenuBarExtra(ProductInfo.name, systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 12) {
                Text(ProductInfo.name)
                    .font(.headline)

                Divider()

                SettingsLink {
                    Text("Settings")
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text(ProductInfo.name)
                .frame(width: 360, height: 220)
        }
    }
}
