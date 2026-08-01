import SwiftUI
import VercelAnalyticsCore

struct SettingsRootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ProductInfo.name)
                .font(.title2.weight(.semibold))

            Text("Vercel account connection and project preferences will be added in a later milestone.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }
}
