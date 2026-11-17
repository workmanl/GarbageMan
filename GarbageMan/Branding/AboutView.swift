import SwiftUI
import AppKit

struct AboutView: View {
    private let appName: String = "GarbageMan"
    private let tagline = "Premium cleanup tools, quietly engineered."
    private let copyright = "© 2026 Emerald Labs"

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = (info["CFBundleShortVersionString"] as? String) ?? "0.0"
        let build = (info["CFBundleVersion"] as? String) ?? "0"
        return "Version \(short) (\(build))"
    }

    private var appIcon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 110, height: 110)
                .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 26, weight: .semibold))
                Text("by Emerald Labs")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(tagline)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)

            Text(version)
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://emeraldlabs.gumroad.com")!) {
                    Label("Gumroad", systemImage: "bag")
                }
                Link(destination: URL(string: "https://emeraldlabs.co")!) {
                    Label("Website", systemImage: "globe")
                }
            }
            .buttonStyle(.bordered)

            Text(copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 360, height: 380)
        .background(
            RadialGradient(
                colors: [
                    Color(red: 0.22, green: 0.47, blue: 0.33).opacity(0.18),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 30,
                endRadius: 360
            )
        )
    }
}

#Preview {
    AboutView()
}
