import PullBullKit
import SwiftUI

/// Settings → Ask: the switch, the Anthropic key (checked on Save), the model, the repos never indexed,
/// what is sent, the index's state with Rebuild, and the cost note.
struct AskSettingsTab: View {
    @Bindable var model: AppModel
    @State private var keyText = ""
    @State private var selectedRepo: String?

    private var isOn: Bool { model.settings.askEnabled }
    private static let keysURL = URL(string: "https://platform.claude.com/settings/keys")!

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { isOn }, set: { model.setAskEnabled($0) })) {
                    RowLabel("Ask AI", note: "Find PRs and issues by description, answered by Claude with your own key.")
                }
            }
            Section {
                keyRow
                keyStatus
            } header: {
                Text("Anthropic API key")
            } footer: {
                Link("Get a key in the Claude Console", destination: Self.keysURL)
                    .font(.system(size: 11))
            }
            Section {
                Picker("Model", selection: modelSelection) {
                    ForEach(model.askModelChoices) { Text($0.name).tag($0.id) }
                }
                .disabled(!isOn)
            }
            Section {
                excludeList
                    .frame(height: 120)
                    .listRowInsets(EdgeInsets())
                    .disabled(!isOn)
            } header: {
                Text("Exclude from Ask AI")
            } footer: {
                Text("Excluded repositories are never indexed or sent.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Ask AI sends your question and up to 40 matching PR and issue descriptions to Anthropic. Nothing is sent until you ask, except a check of the key when you save it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isOn {
                Section {
                    indexStatus
                } header: {
                    Text("Index")
                }
            }
            Section {
                Text("No spending cap in PullBull. Set limits in the Anthropic console.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        // It always fits; without this a scroller can flash in after the window resizes for this tab.
        .scrollDisabled(true)
        .onAppear { model.loadAskKeyState() }
    }

    // MARK: Key

    private var keyRow: some View {
        HStack(spacing: 8) {
            SecureField("Anthropic API key", text: $keyText, prompt: Text("sk-ant-…"))
                .labelsHidden()
                .onSubmit(saveKey)
                .accessibilityLabel("Anthropic API key")
            Button("Save", action: saveKey)
                .disabled(!isOn || model.askKeyState == .checking
                    || keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Remove") {
                keyText = ""
                model.removeAskKey()
            }
            .disabled(model.askKeyState == .none || model.askKeyState == .checking)
        }
    }

    @ViewBuilder
    private var keyStatus: some View {
        switch model.askKeyState {
        case .none:
            Text(isOn ? "No key saved." : "Turn Ask AI on to save a key.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking the key…")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        case .valid:
            Label("Key saved", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .invalid(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        }
    }

    private func saveKey() {
        let typed = keyText
        Task {
            await model.saveAskKey(typed)
            if model.askKeyState == .valid, keyText == typed { keyText = "" }
        }
    }

    // MARK: Model

    /// An unknown saved ID shows as the model Ask actually uses.
    private var modelSelection: Binding<String> {
        Binding(
            get: { AskModel.named(model.settings.askModel, in: model.askModelChoices).id },
            set: { model.settings.askModel = $0 })
    }

    // MARK: Exclude list

    private var excludeList: some View {
        VStack(spacing: 0) {
            if model.settings.askExcludedRepos.isEmpty {
                Text("No repositories excluded.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedRepo) {
                    ForEach(model.settings.askExcludedRepos, id: \.self) { repo in
                        Text(repo).font(.system(size: 12)).tag(repo)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(false)
            }
            Divider()
            HStack(spacing: 0) {
                Menu {
                    ForEach(model.askExcludeCandidates, id: \.self) { repo in
                        Button(repo) { model.setAskExcluded(model.settings.askExcludedRepos + [repo]) }
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 24, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(model.askExcludeCandidates.isEmpty)
                .help("Exclude a repository")
                .accessibilityLabel("Exclude a repository")
                Divider().frame(height: 16)
                Button {
                    guard let repo = selectedRepo else { return }
                    model.setAskExcluded(model.settings.askExcludedRepos.filter { $0 != repo })
                    selectedRepo = nil
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 22)
                }
                .disabled(selectedRepo.map { !model.settings.askExcludedRepos.contains($0) } ?? true)
                .help("Include the selected repository again")
                .accessibilityLabel("Include the selected repository again")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .frame(height: 26)
        }
    }

    // MARK: Index

    private var indexStatus: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let progress = model.askProgress {
                    Text("^[\(progress.indexed) item](inflect: true) indexed")
                    Group {
                        if progress.backfilling, let total = progress.estimatedTotal {
                            Text("Backfilling: \(progress.indexed) of ~\(total)")
                        } else if let lastSync = progress.lastSync {
                            Text("Last sync \(lastSync, format: .relative(presentation: .named))")
                        } else {
                            Text("Not synced yet")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                } else if let error = model.askOpenError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("Indexing starts once an account is running.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Rebuild") { model.rebuildAskIndex() }
                .disabled(model.askProgress == nil)
                .help("Empty the index and fetch it again")
        }
    }
}
