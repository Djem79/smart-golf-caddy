// ios/SmartGolfCaddy/App/RootView.swift
import SwiftUI

struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.golf")
                .font(.system(size: 56))
            Text("Smart Golf Caddy")
                .font(.title)
        }
    }
}
