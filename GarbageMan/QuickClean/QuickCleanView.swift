import SwiftUI

struct QuickCleanView: View {
    @State private var model = QuickCleanModel()
    @State private var showConfirm = false
    @State private var showOutcome = false
    @State private var showEmptyTrashConfirm = false
    @State private var lastTrashOutcome: TrashEmptier.Outcome?
    @State private var showTrashOutcome = false
    @State private var focusedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showsKPIStrip {
                kpiStrip
                Divider()
            }
            list
            Divider()
            footer
        }
        .task {
            // Auto-scan the first time this tab appears so the user never
            // sees a dead "all dashes" list. Re-entering the tab uses the
            // last scan's data without re-walking.
            if model.state == .idle {
                await model.scan()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick Clean")
                    .font(.title.weight(.semibold))
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { Task { await model.scan() } }) {
                Label(scanButtonTitle, systemImage: "arrow.clockwise")
            }
            .disabled(model.state == .scanning)
        }
        .padding(20)
    }

    private var headerSubtitle: String {
        switch model.state {
        case .idle: return "Scan reclaimable caches, logs, and developer detritus."
        case .scanning: return "Scanning every category in parallel…"
        case .cleaning:
            if model.cleanTotalCategoryCount == 0 {
                return "Moving items to Trash…"
            }
            return "Cleaning \(min(model.cleanCompletedCount + 1, model.cleanTotalCategoryCount)) of \(model.cleanTotalCategoryCount) categories…"
        case .ready:
            let total = model.totalBytes.formattedByteCount
            let date = model.lastScanCompletedAt.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .short) } ?? ""
            return "Found \(total) across \(model.visibleRows.count) categories\(date.isEmpty ? "" : " (\(date))")."
        }
    }

    private var scanButtonTitle: String {
        switch model.state {
        case .idle: return "Scan"
        case .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        case .ready: return "Rescan"
        }
    }

    private var list: some View {
        List(selection: $focusedRowID) {
            ForEach(model.sections) { group in
                Section(group.section.title) {
                    ForEach(group.rows) { row in
                        CategoryRowView(
                            row: row,
                            isSelected: Binding(
                                get: { row.isSelected },
                                set: { model.setSelection(for: row.id, to: $0) }
                            ),
                            isActivelyCleaning: isActivelyCleaning(row),
                            trailingAction: trailingAction(for: row)
                        )
                        .tag(row.id)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .onKeyPress(.space) {
            guard let id = focusedRowID,
                  let row = model.rows.first(where: { $0.id == id }),
                  row.hasResolvedPaths else { return .ignored }
            model.setSelection(for: id, to: !row.isSelected)
            return .handled
        }
    }

    private func trailingAction(for row: QuickCleanModel.CategoryRow) -> CategoryRowView.TrailingAction? {
        guard row.id == "trash", (row.size ?? 0) > 0 else { return nil }
        return CategoryRowView.TrailingAction(
            label: "Empty…",
            help: "Permanently delete every item in the system Trash."
        ) {
            showEmptyTrashConfirm = true
        }
    }

    private func isActivelyCleaning(_ row: QuickCleanModel.CategoryRow) -> Bool {
        model.state == .cleaning && model.currentCleaningCategoryID == row.id
    }

    private var showsKPIStrip: Bool {
        switch model.state {
        case .ready, .cleaning: return true
        case .idle, .scanning: return false
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: 0) {
            kpiTile(label: "RECLAIMABLE", value: model.totalBytes, tone: .primary)
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1)
            kpiTile(label: "SELECTED", value: model.totalSelectedBytes, tone: .accent)
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1)
            kpiTile(label: "CATEGORIES", count: model.cleanableRows.count, total: model.visibleRows.count)
        }
        .frame(height: 64)
    }

    private enum KPITone { case primary, accent }

    @ViewBuilder
    private func kpiTile(label: String, value: UInt64, tone: KPITone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(value.formattedByteCount)
                .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tone == .accent ? Color.accentColor : .primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func kpiTile(label: String, count: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                Text("/ \(total)")
                    .font(.system(size: 14, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button("Select All") { model.toggleAll(true) }
                .keyboardShortcut("a", modifiers: [.command])
            Button("Deselect All") { model.toggleAll(false) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Spacer()
            VStack(alignment: .trailing) {
                Text("Selected: \(model.totalSelectedBytes.formattedByteCount)")
                    .font(.headline.monospacedDigit())
                Text("\(model.selectedCount) of \(model.visibleRows.count) categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.state == .cleaning {
                Button(role: .destructive, action: { model.cancelClean() }) {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .help("Stop after the current category finishes.")
            } else {
                Button(action: { showConfirm = true }) {
                    Label("Clean", systemImage: "trash")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasCleanableSelection || model.state == .scanning)
                .help("Move selected categories' contents to the Trash. Trash itself is skipped for now.")
            }
        }
        .padding(20)
        .confirmationDialog(
            confirmMessage,
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    model.startClean()
                    await model.waitForCleanToFinish()
                    showOutcome = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(confirmDetail)
        }
        .alert(
            outcomeTitle,
            isPresented: $showOutcome,
            presenting: model.lastCleanOutcome
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { outcome in
            Text(outcomeMessage(outcome))
        }
        .confirmationDialog(
            "Empty the Trash?",
            isPresented: $showEmptyTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("Permanently Empty", role: .destructive) {
                Task {
                    let outcome = await model.emptyTrash()
                    lastTrashOutcome = outcome
                    showTrashOutcome = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete every item in your Trash. It cannot be undone.")
        }
        .alert(
            "Trash Emptied",
            isPresented: $showTrashOutcome,
            presenting: lastTrashOutcome
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { outcome in
            var lines = ["Removed \(outcome.removed) item(s) · \(outcome.bytesReclaimed.formattedByteCount) reclaimed."]
            if outcome.failed > 0 { lines.append("\(outcome.failed) failed.") }
            if let err = outcome.firstError { lines.append("First error: \(err)") }
            return Text(lines.joined(separator: "\n"))
        }
    }

    private var confirmMessage: String {
        "Move \(model.cleanableRows.count) categories to Trash?"
    }

    private var confirmDetail: String {
        let bytes = model.cleanableBytes.formattedByteCount
        let trashSkipped = model.rows.contains { $0.isSelected && QuickCleanModel.cleanExcludedCategoryIDs.contains($0.id) }
        let suffix = trashSkipped ? " The Trash category is left alone for now." : ""
        return "≈\(bytes) of cached files will be moved to your Trash. You can restore them until the Trash is emptied.\(suffix)"
    }

    private var outcomeTitle: String {
        guard let outcome = model.lastCleanOutcome else { return "Done" }
        if outcome.failed == 0 { return "Cleaned" }
        if outcome.recycled == 0 { return "Couldn't clean" }
        return "Cleaned with errors"
    }

    private func outcomeMessage(_ outcome: QuickCleanModel.CleanOutcome) -> String {
        var parts: [String] = []
        parts.append("Moved \(outcome.recycled) item(s) to Trash (~\(outcome.bytesReclaimedEstimate.formattedByteCount)).")
        if outcome.failed > 0 {
            parts.append("\(outcome.failed) item(s) failed.")
        }
        if let err = outcome.errorMessage {
            parts.append("First error: \(err)")
        }
        return parts.joined(separator: "\n")
    }
}

private struct CategoryRowView: View {
    struct TrailingAction {
        let label: String
        let help: String
        let action: () -> Void
    }

    let row: QuickCleanModel.CategoryRow
    @Binding var isSelected: Bool
    var isActivelyCleaning: Bool = false
    var trailingAction: TrailingAction?

    var body: some View {
        HStack(spacing: 12) {
            if isActivelyCleaning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18)
            } else {
                Toggle("", isOn: $isSelected)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(!row.hasResolvedPaths)
            }
            Image(systemName: row.category.symbol)
                .frame(width: 22)
                .foregroundStyle(row.hasResolvedPaths ? .secondary : .tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.category.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(row.hasResolvedPaths ? .primary : .secondary)
                Text(row.category.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            reclaimedBadge
            warningGlyph
            sizeView
            revealButton
            if let action = trailingAction {
                Button(action: action.action) {
                    Text(action.label).font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(action.help)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.3), value: row.lastReclaimed)
    }

    @ViewBuilder
    private var reclaimedBadge: some View {
        if let amount = row.lastReclaimed, amount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("−\(amount.formattedByteCount)")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
            .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
        }
    }

    @ViewBuilder
    private var warningGlyph: some View {
        if !row.unreadablePaths.isEmpty {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help(warningTooltip)
                .imageScale(.medium)
        }
    }

    private var warningTooltip: String {
        let count = row.unreadablePaths.count
        let preview = row.unreadablePaths.prefix(3).map(\.path).joined(separator: "\n")
        let suffix = count > 3 ? "\n…and \(count - 3) more" : ""
        return "\(count) path(s) couldn't be read (permission?):\n\(preview)\(suffix)"
    }

    @ViewBuilder
    private var revealButton: some View {
        if let url = row.primaryPath {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Reveal \(url.path) in Finder")
        } else {
            Color.clear.frame(width: 18, height: 18)
        }
    }

    @ViewBuilder
    private var sizeView: some View {
        if row.isScanning {
            ProgressView().controlSize(.small)
        } else if !row.hasResolvedPaths {
            Text("Not installed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if let size = row.size {
            if size == 0 {
                Text("Empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(size.formattedByteCount)
                    .font(.body.monospacedDigit())
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

#Preview {
    QuickCleanView()
        .frame(width: 720, height: 520)
}
