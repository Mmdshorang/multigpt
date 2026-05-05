import SwiftUI

extension SettingsContentView {
    struct DataPane: View {
        @ObservedObject var viewModel: AccountsMenuViewModel
        @State private var isExporting = false
        @State private var isImporting = false
        @State private var importResult: AccountExportService.ImportResult?
        @State private var exportError: String?
        @State private var importError: String?

        var body: some View {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Backup & Restore")
                        .font(.headline)

                    Text("Export all accounts and preferences to a JSON file. Import restores them on any Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            performExport()
                        } label: {
                            Label("Export Accounts", systemImage: "square.and.arrow.up")
                        }
                        .disabled(isExporting)

                        Button {
                            isImporting = true
                        } label: {
                            Label("Import Accounts", systemImage: "square.and.arrow.down")
                        }
                        .fileImporter(
                            isPresented: $isImporting,
                            allowedContentTypes: [.json],
                            allowsMultipleSelection: false
                        ) { result in
                            performImport(result: result)
                        }
                    }

                    if let error = exportError {
                        Text("Export failed: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let error = importError {
                        Text("Import failed: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let result = importResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import complete")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("\(result.imported) imported, \(result.skipped) skipped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !result.conflicts.isEmpty {
                                Text("Skipped (already exist): \(result.conflicts.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Exported files contain auth tokens. Store them securely.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private func performExport() {
            isExporting = true
            exportError = nil
            importResult = nil

            guard let service = viewModel.accountService as? CodexAccountService else {
                exportError = "Service unavailable"
                isExporting = false
                return
            }

            do {
                let data = try AccountExportService.exportData(
                    accountService: service,
                    preferencesStore: viewModel.preferences
                )

                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "multicodex-backup.json"
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        do {
                            try AccountExportService.writeBackupData(data, to: url)
                        } catch {
                            exportError = error.localizedDescription
                        }
                    }
                    isExporting = false
                }
            } catch {
                exportError = error.localizedDescription
                isExporting = false
            }
        }

        private func performImport(result: Result<[URL], Error>) {
            importError = nil
            importResult = nil

            guard let service = viewModel.accountService as? CodexAccountService else {
                importError = "Service unavailable"
                return
            }

            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    var prefs = viewModel.preferences
                    let importResult = try AccountExportService.importAccounts(
                        from: url,
                        accountService: service,
                        preferencesStore: &prefs
                    )
                    viewModel.preferences = prefs
                    viewModel.reloadPreferencesFromStore()
                    self.importResult = importResult
                    viewModel.refreshLive()
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
    }
}
