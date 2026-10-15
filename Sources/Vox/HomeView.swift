import AppKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StatsRow(history: store.history)

                if store.history.isEmpty {
                    EmptyHistory(shortcut: store.profiles.first?.shortcut)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.day) { group in
                            Text(dayTitle(group.day))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.top, group.day == groups.first?.day ? 0 : 14)
                                .padding(.bottom, 2)
                            ForEach(group.items) { item in
                                TranscriptCard(transcript: item)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
        .searchable(text: $search, placement: .toolbar, prompt: "Search transcripts")
        .toolbar {
            ToolbarItem {
                Button {
                    confirmClear = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .help("Clear history")
                .disabled(store.history.isEmpty)
            }
        }
        .confirmationDialog("Clear all transcription history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var filtered: [Transcript] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.history }
        return store.history.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.profileName.localizedCaseInsensitiveContains(query)
        }
    }

    private var groups: [(day: Date, items: [Transcript])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

private struct StatsRow: View {
    let history: [Transcript]

    var body: some View {
        HStack(spacing: 12) {
            StatTile(title: "Today", value: "\(todayCount)", caption: todayCount == 1 ? "transcription" : "transcriptions", symbol: "calendar")
            StatTile(title: "Words dictated", value: totalWords.formatted(), caption: "all time", symbol: "text.word.spacing")
            StatTile(title: "Time speaking", value: speakingTime, caption: "all time", symbol: "waveform")
        }
    }

    private var todayCount: Int {
        history.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    private var totalWords: Int {
        history.reduce(0) { $0 + $1.wordCount }
    }

    private var speakingTime: String {
        let seconds = Int(history.reduce(0) { $0 + $1.duration })
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

private struct EmptyHistory: View {
    let shortcut: Shortcut?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.primary)
            Text("No transcriptions yet")
                .font(.title3.weight(.semibold))
            if let shortcut {
                HStack(spacing: 6) {
                    Text("Press")
                    KeycapsView(shortcut: shortcut)
                    Text("anywhere to start dictating.")
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct TranscriptCard: View {
    let transcript: Transcript
    @EnvironmentObject private var store: AppStore
    @State private var hovering = false
    @State private var copied = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(transcript.text)
                .font(.body)
                .lineSpacing(2)
                .lineLimit(expanded ? nil : 4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Text(transcript.profileName)
                    .font(.caption.weight(.medium))
                Text(transcript.date.formatted(date: .omitted, time: .shortened))
                Text("\(transcript.wordCount) words")
                Spacer()

                if hovering {
                    Button {
                        store.deleteTranscript(transcript.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                    .transition(.opacity)
                }
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.2 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering }
        }
        .onTapGesture(count: 2) { expanded.toggle() }
        .contextMenu {
            Button("Copy", action: copy)
            Button(expanded ? "Collapse" : "Expand") { expanded.toggle() }
            Divider()
            Button("Delete", role: .destructive) { store.deleteTranscript(transcript.id) }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript.text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copied = false }
        }
    }
}
