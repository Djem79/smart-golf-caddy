import SwiftUI

struct WatchRootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.golf")
                .font(.system(size: 28))
                .foregroundStyle(DSColor.primary)
            Text("Раунд не начат")
                .font(DSFont.labelLG)
                .multilineTextAlignment(.center)
            Text("Начните раунд на телефоне")
                .font(DSFont.labelMD)
                .foregroundStyle(DSColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
