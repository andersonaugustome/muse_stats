import SwiftUI

enum Muse {
    static let accent = Color(red: 0.0, green: 0.48, blue: 1.0) // azul Meta/Muse
    static let accentSoft = accent.opacity(0.12)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let sub = Color.secondary
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .background(Muse.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

struct Ring: View {
    var fraction: Double
    var percent: Int
    var size: CGFloat = 148
    var lineWidth: CGFloat = 13
    var caption: String = "uso atual"

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(Muse.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: fraction)
            VStack(spacing: 2) {
                Text(percent >= 0 ? "\(percent)%" : "—")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                Text(caption).font(.caption2).foregroundStyle(Muse.sub)
            }
        }
        .frame(width: size, height: size)
    }
}

struct UsageBar: View {
    var title: String
    var percent: Int
    var fraction: Double
    var resetsIn: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(percent >= 0 ? "\(percent)% usado" : "indisponível")
                    .font(.caption).foregroundStyle(Muse.sub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(barColor)
                        .frame(width: geo.size.width * max(0.02, min(1, fraction)))
                        .animation(.easeInOut(duration: 0.8), value: fraction)
                }
            }
            .frame(height: 8)
            Text("Reseta em \(resetsIn)").font(.caption2).foregroundStyle(Muse.sub)
        }
    }

    private var barColor: Color {
        switch fraction {
        case ..<0.6: return Muse.accent
        case ..<0.85: return .orange
        default: return .red
        }
    }
}

struct StatTile: View {
    var icon: String
    var value: String
    var label: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Muse.accent)
                    .frame(width: 30, height: 30)
                    .background(Muse.accentSoft, in: RoundedRectangle(cornerRadius: 9))
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label).font(.caption).foregroundStyle(Muse.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WeekChart: View {
    var days: [DayUsage]

    var body: some View {
        let maxTurns = max(days.map(\.turns).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(days) { day in
                VStack(spacing: 7) {
                    Text("\(day.turns)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Muse.accent : .clear)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Calendar.current.isDateInToday(day.date) ? Muse.accent : Muse.accent.opacity(0.28))
                        .frame(height: max(6, 84 * CGFloat(day.turns) / CGFloat(maxTurns)))
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.caption2).foregroundStyle(Muse.sub)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 122, alignment: .bottom)
    }
}
