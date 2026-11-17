import SwiftUI
import AppKit

struct DiskInspectorView: View {
    @State private var model = DiskInspectorModel()
    @State private var filterQuery: String = ""
    @FocusState private var isFilterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            breadcrumb
            Divider()
            if !model.topEntries.isEmpty || !filterQuery.isEmpty {
                filterRow
                Divider()
            }
            content
        }
        .task {
            if model.phase == .idle { await model.scan() }
        }
        .onChange(of: model.currentRoot) {
            filterQuery = ""
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Inspector")
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.scan(forceRescan: true) }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.phase == .scanning)
        }
        .padding(20)
    }

    private var subtitle: String {
        switch model.phase {
        case .idle: return "Tap Rescan to find the largest folders here."
        case .scanning: return "Walking the directory tree…"
        case .ready:
            let total = model.entries.reduce(UInt64(0)) { $0 &+ $1.size }
            let shown = model.topEntries.count
            let overflow = model.entries.count - shown
            let when = model.lastScannedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
            let extras = overflow > 0 ? " (+\(overflow) smaller hidden)" : ""
            return "\(shown) folders · \(total.formattedByteCount)\(extras) · scanned at \(when)"
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                Task { while model.canPop { await model.pop() } }
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canPop)

            ForEach(Array(model.breadcrumbs.enumerated()), id: \.offset) { idx, url in
                if idx > 0 {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                Text(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(idx == model.breadcrumbs.count - 1 ? .primary : .secondary)
            }
            Spacer()
            if model.canPop {
                Button("Up") { Task { await model.pop() } }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                    .background(
                        // Mirror ⌘← onto the same action without making it
                        // user-visible as a duplicate button.
                        Button("") { Task { await model.pop() } }
                            .keyboardShortcut(.leftArrow, modifiers: [.command])
                            .opacity(0)
                            .frame(width: 0, height: 0)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $filterQuery, prompt: Text("Filter by name…"))
                .textFieldStyle(.roundedBorder)
                .focused($isFilterFocused)
            if !filterQuery.isEmpty {
                Button {
                    filterQuery = ""
                    isFilterFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear filter")
                Text("\(filteredEntries.count) of \(model.topEntries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var filteredEntries: [FolderSizer.Entry] {
        guard !filterQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return model.topEntries
        }
        let needle = filterQuery.lowercased()
        return model.topEntries.filter { $0.displayName.lowercased().contains(needle) }
    }

    @ViewBuilder
    private var content: some View {
        if model.phase == .scanning && model.topEntries.isEmpty {
            firstScanSpinner
        } else if model.topEntries.isEmpty && model.phase == .ready {
            emptyState
        } else {
            entriesList
                .opacity(model.phase == .scanning ? 0.45 : 1.0)
                .allowsHitTesting(model.phase != .scanning)
                .overlay(alignment: .top) {
                    if model.phase == .scanning {
                        scanningBanner
                            .padding(.top, 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: model.phase)
        }
    }

    private var firstScanSpinner: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Sizing children of \(model.currentRoot.lastPathComponent)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 36, weight: .light))
            Text("Nothing under \(model.currentRoot.lastPathComponent).")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var entriesList: some View {
        let visible = filteredEntries
        if visible.isEmpty && !filterQuery.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text("No matches for \"\(filterQuery)\"")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(visible) { entry in
                EntryRow(
                    entry: entry,
                    maxBytes: maxBytes,
                    onDrill: {
                        guard entry.isDirectory else {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                            return
                        }
                        Task { await model.drill(into: entry.url) }
                    },
                    onReveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    }
                )
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var scanningBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Sizing \(model.currentRoot.lastPathComponent)…")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        )
        .overlay(
            Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private var maxBytes: UInt64 { model.topEntries.first?.size ?? 1 }
}

private struct EntryRow: View {
    let entry: FolderSizer.Entry
    let maxBytes: UInt64
    let onDrill: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName).font(.body.weight(.medium))
                bar
            }
            Spacer()
            Text(entry.size.formattedByteCount)
                .font(.body.monospacedDigit())
                .frame(width: 90, alignment: .trailing)
            Button(action: onReveal) {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onDrill)
        .help(entry.url.path)
        .padding(.vertical, 2)
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
    }

    private var fraction: CGFloat {
        guard maxBytes > 0 else { return 0 }
        return CGFloat(Double(entry.size) / Double(maxBytes))
    }
}
