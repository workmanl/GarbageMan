import SwiftUI
import UniformTypeIdentifiers

struct UninstallerView: View {
    @State private var model = UninstallerModel()
    @State private var isTargeted = false
    @State private var showConfirm = false
    @State private var showOutcome = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Uninstaller")
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.bundle != nil {
                Button("Choose Another") { model.clear() }
            }
        }
        .padding(20)
    }

    private var subtitle: String {
        switch model.phase {
        case .empty: return "Drag an app from /Applications to find every trace of it."
        case .scanning: return "Sniffing out leftovers…"
        case .ready:
            guard let b = model.bundle else { return "" }
            return "\(b.displayName) — \(b.bundleIdentifier)"
        case .uninstalling: return "Sending app and leftovers to Trash…"
        case .done:
            guard let o = model.lastOutcome else { return "Done." }
            return "Sent \(o.recycled) item(s) to Trash · ~\(o.bytesReclaimedEstimate.formattedByteCount)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .empty:
            dropZone
        case .scanning:
            scanningView
        case .ready, .uninstalling, .done:
            leftoversList
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "shippingbox.and.arrow.backward")
                .font(.system(size: 56, weight: isTargeted ? .semibold : .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .scaleEffect(isTargeted ? 1.18 : 1.0)
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isTargeted)
            Text(isTargeted ? "Drop to scan" : "Drop a .app here")
                .font(.title3.weight(.semibold))
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)
            Text("We never delete anything. Leftovers go to the Trash.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: isTargeted ? [] : [8, 6])
                )
        )
        .padding(20)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    @ViewBuilder
    private var scanningView: some View {
        VStack(spacing: 20) {
            if let bundle = model.bundle {
                BundleHeaderCard(bundle: bundle)
                    .padding(.horizontal, 20)
            }
            VStack(spacing: 8) {
                ProgressView()
                Text("Sniffing out leftovers…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var leftoversList: some View {
        VStack(spacing: 0) {
            if let bundle = model.bundle {
                BundleHeaderCard(bundle: bundle)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Toggle(isOn: $model.includeAppItself) {
                if let b = model.bundle {
                    Label("Include \(b.displayName).app (\(model.approxAppSize.formattedByteCount))", systemImage: "app.dashed")
                } else {
                    Text("Include app")
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            List {
                ForEach(model.groupedRows, id: \.group) { section in
                    Section(section.group) {
                        ForEach(section.rows) { row in
                            LeftoverRowView(
                                row: row,
                                isSelected: Binding(
                                    get: { row.isSelected },
                                    set: { model.setSelection(for: row.id, $0) }
                                )
                            )
                        }
                    }
                }
                if model.groupedRows.isEmpty {
                    Section {
                        Text("No leftovers found. Clean uninstall.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var footer: some View {
        HStack {
            if model.phase == .ready {
                Text("\(model.selectedRows.count) of \(model.rows.count) leftovers selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Selected: \(model.totalSelectedBytes.formattedByteCount)")
                    .font(.headline.monospacedDigit())
            }
            Button(action: { showConfirm = true }) {
                Label(uninstallButtonTitle, systemImage: "trash")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.phase != .ready)
        }
        .padding(20)
        .confirmationDialog("Uninstall \(model.bundle?.displayName ?? "this app")?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    await model.uninstall()
                    showOutcome = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(confirmMessage)
        }
        .alert("Uninstalled", isPresented: $showOutcome, presenting: model.lastOutcome) { _ in
            Button("OK", role: .cancel) { }
        } message: { outcome in
            var lines = ["Moved \(outcome.recycled) item(s) to Trash (~\(outcome.bytesReclaimedEstimate.formattedByteCount))."]
            if outcome.failed > 0 { lines.append("\(outcome.failed) failed.") }
            if outcome.appLeftInstalled {
                lines.append("The app itself was not moved and is still installed. You can drag it to the Trash in Finder, which can ask for your password.")
            }
            if let err = outcome.errorMessage { lines.append("First error: \(err)") }
            return Text(lines.joined(separator: "\n"))
        }
    }

    private var uninstallButtonTitle: String {
        switch model.phase {
        case .uninstalling: return "Uninstalling…"
        case .done: return "Done"
        default: return "Uninstall"
        }
    }

    private var confirmMessage: String {
        let appPart = model.includeAppItself ? "the app and " : ""
        let count = model.selectedRows.count
        let bytes = model.totalSelectedBytes.formattedByteCount
        return "Move \(appPart)\(count) leftover(s) — about \(bytes) — to the Trash?"
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { await model.acceptDrop(urls: [url]) }
            }
        }
    }
}

private struct BundleHeaderCard: View {
    let bundle: AppBundle

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundle.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(bundle.displayName).font(.title3.weight(.semibold))
                Text(bundle.bundleIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let v = bundle.version {
                    Text("v\(v)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct LeftoverRowView: View {
    let row: UninstallerModel.LeftoverRow
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Image(systemName: row.leftover.kind == .directory ? "folder" : "doc")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.leftover.displayName).font(.body.weight(.medium))
                Text(row.leftover.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let size = row.size {
                Text(size == 0 ? "—" : size.formattedByteCount).font(.body.monospacedDigit())
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
