import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $store.selectedProfileID) {
                ForEach(store.profiles) { profile in
                    ProfileRow(profile: profile).tag(profile.id)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(width: 250)

            Divider()

            if let id = store.selectedProfileID, store.profile(id) != nil {
                ProfileEditor(profile: binding(for: id))
                    .id(id)
            } else {
                ContentUnavailableView("No Profile Selected", systemImage: "person.crop.rectangle.stack",
                                       description: Text("Pick a profile or create a new one."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Profiles")
        .toolbar {
            ToolbarItem {
                Button {
                    store.addProfile()
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .help("New profile")
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Profile> {
        Binding {
            store.profile(id) ?? Profile.dictation(systemPrompt: "")
        } set: { updated in
            if let index = store.profiles.firstIndex(where: { $0.id == id }) {
                store.profiles[index] = updated
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 10) {
            ProfileIconView(symbol: profile.icon, color: profile.color, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name.isEmpty ? "Untitled" : profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let shortcut = profile.shortcut {
                    KeycapsView(shortcut: shortcut, compact: true)
                } else {
                    Text("No shortcut").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileEditor: View {
    @Binding var profile: Profile
    @EnvironmentObject private var store: AppStore
    @AppStorage(PrefKey.defaultModel) private var defaultModel = Prefs.fallbackModel
    @State private var showAppearance = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Button {
                        showAppearance = true
                    } label: {
                        ProfileIconView(symbol: profile.icon, color: profile.color, size: 52)
                    }
                    .buttonStyle(.plain)
                    .help("Change icon and color")
                    .popover(isPresented: $showAppearance, arrowEdge: .bottom) {
                        AppearancePicker(icon: $profile.icon, color: $profile.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Profile name", text: $profile.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold))
                        Text(modelSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: $profile.shortcut)
                }
                if let conflict {
                    Label("Same shortcut as \(conflict). Only one of them will respond.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Activation")
            } footer: {
                Text("Use at least one modifier: fn, ⌃, ⌥, ⇧ or ⌘.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                ModelPicker(title: "Model", model: $profile.model, defaultModel: defaultModel)
            }

            Section {
                TextEditor(text: $profile.systemPrompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Describe who's talking and how the text should come out, e.g. \"I'm a software engineer; keep technical terms like Kubernetes and PostgreSQL exact.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Delete Profile", role: .destructive) { confirmDelete = true }
                    .disabled(store.profiles.count <= 1)
            } footer: {
                if store.profiles.count <= 1 {
                    Text("You need at least one profile.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete \"\(profile.name)\"?", isPresented: $confirmDelete) {
            Button("Delete Profile", role: .destructive) { store.deleteProfile(profile.id) }
        }
    }

    private var modelSummary: String {
        let model = profile.model.trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? "Uses the default model · \(defaultModel)" : model
    }

    private var conflict: String? {
        guard let shortcut = profile.shortcut else { return nil }
        return store.profiles.first { $0.id != profile.id && $0.shortcut == shortcut }?.name
    }
}

private struct AppearancePicker: View {
    @Binding var icon: String
    @Binding var color: ProfileColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(ProfileColor.allCases, id: \.self) { option in
                    Circle()
                        .fill(option.color.gradient)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.white, lineWidth: option == color ? 2 : 0))
                        .shadow(color: option == color ? option.color.opacity(0.6) : .clear, radius: 3)
                        .onTapGesture { color = option }
                }
            }
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
                ForEach(Profile.icons, id: \.self) { symbol in
                    Button {
                        icon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(symbol == icon ? color.color.opacity(0.25) : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(symbol == icon ? color.color : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
    }
}
