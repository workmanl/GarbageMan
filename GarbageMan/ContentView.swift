import SwiftUI

struct ContentView: View {
    @State private var selection: Feature = .quickClean

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.title, systemImage: feature.symbol)
                    .tag(feature)
            }
            .navigationTitle("GarbageMan")
            .listStyle(.sidebar)
        } detail: {
            switch selection {
            case .quickClean:
                QuickCleanView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .uninstaller:
                UninstallerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .diskInspector:
                DiskInspectorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                FeaturePlaceholder(feature: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFeature)) { note in
            if let feature = Feature(showRequest: note) { selection = feature }
        }
    }
}

struct FeaturePlaceholder: View {
    let feature: Feature

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: feature.symbol)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(feature.title)
                .font(.title2.weight(.semibold))
            Text("Coming online in the next iteration.")
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

#Preview {
    ContentView()
        .frame(width: 800, height: 520)
}
