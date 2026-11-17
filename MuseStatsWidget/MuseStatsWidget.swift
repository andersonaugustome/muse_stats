import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .demo) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: SharedStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: SharedStore.load())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private var accent: Color { Color(red: 0.0, green: 0.48, blue: 1.0) }

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: Entry

    var body: some View {
        let s = entry.snapshot
        switch family {
        case .systemLarge: large(s)
        case .systemMedium: medium(s)
        default: small(s)
        }
    }

    private func small(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Muse", systemImage: "waveform.path.ecg").font(.caption.weight(.bold)).foregroundStyle(accent)
            Text(s.windowUsedPercent >= 0 ? "\(s.windowUsedPercent)%" : "—").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("uso atual · reseta em \(Fmt.countdown(to: s.windowResetsAt))").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: s.windowFraction).tint(accent)
            Text("Weekly: \(s.weeklyUsedPercent >= 0 ? "\(s.weeklyUsedPercent)%" : "—") · \(Fmt.count(s.todayTokens)) tokens hoje").font(.caption2).foregroundStyle(.secondary)
            Text(s.account.subscriptionActive ? "Assinatura ativa" : "Muse")
                .font(.caption2.weight(.semibold)).foregroundStyle(.green)
        }.padding(4)
    }

    private func medium(_ s: UsageSnapshot) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Muse · \(s.modelID)", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.bold)).foregroundStyle(accent).lineLimit(1)
                Text("\(s.windowUsedPercent >= 0 ? "\(s.windowUsedPercent)%" : "—") de uso atual").font(.title3.weight(.bold))
                Text("Weekly \(s.weeklyUsedPercent >= 0 ? "\(s.weeklyUsedPercent)%" : "—") · reseta em \(Fmt.countdown(to: s.weeklyResetsAt))")
                    .font(.caption).foregroundStyle(.secondary)
                ProgressView(value: s.weeklyFraction).tint(accent)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("\(s.weekSessions) na semana", systemImage: "calendar")
                Label("\(s.streakDays) dias seguidos", systemImage: "flame")
                Label("\(s.projectCount) projetos", systemImage: "folder")
            }.font(.caption.weight(.medium))
        }.padding(4)
    }

    private func large(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Muse · \(s.modelID)", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.bold)).foregroundStyle(accent).lineLimit(1)
            HStack(spacing: 18) {
                Stat(label: "Uso atual", value: s.windowUsedPercent >= 0 ? "\(s.windowUsedPercent)%" : "—")
                Stat(label: "Weekly", value: s.weeklyUsedPercent >= 0 ? "\(s.weeklyUsedPercent)%" : "—")
                Stat(label: "Tokens hoje", value: Fmt.count(s.todayTokens))
                Stat(label: "Sequência", value: "\(s.streakDays)d")
            }
            ProgressView(value: s.windowFraction).tint(accent)
            Divider()
            WeekBars(days: s.last7Days)
            if let project = s.topProjects.first {
                Text("Projeto top: \(project.name) · \(project.turns) turnos")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(4)
    }
}

private struct Stat: View {
    var label: String; var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeekBars: View {
    var days: [DayUsage]
    var body: some View {
        let maxTurns = max(days.map(\.turns).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { day in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Calendar.current.isDateInToday(day.date) ? accent : accent.opacity(0.25))
                    .frame(height: max(4, 44 * CGFloat(day.turns) / CGFloat(maxTurns)))
                    .frame(maxWidth: .infinity)
            }
        }.frame(height: 46, alignment: .bottom)
    }
}

@main
struct MuseStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MuseStatsWidget", provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Muse")
        .description("Sessões, turnos e sequência do Muse em um relance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
