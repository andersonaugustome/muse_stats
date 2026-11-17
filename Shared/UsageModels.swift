import Foundation

// MARK: - Conta Muse (Meta) — metadados de ~/.config/muse/auth.json (sem segredos)

struct MuseAccount: Codable {
    var name: String = ""
    var email: String = ""
    var provider: String = "meta"
    var subscriptionActive: Bool = false
    var apiBaseURL: String = ""
    var isLoggedIn: Bool { subscriptionActive || !email.isEmpty }
}

// MARK: - Snapshot de uso do Muse (compartilhado app <-> widget via App Group)
// Fonte real: ~/.local/share/muse/session-index.db (sessões indexadas pelo Muse).
// A Meta não publica limite numérico da assinatura, então o app mostra atividade
// real (sessões/turnos/projetos) — nunca uma % de limite inventada.

struct DayUsage: Codable, Identifiable {
    var date: Date
    var sessions: Int
    var turns: Int
    var tokens: Int = 0
    var id: Date { date }
}

struct ProjectUsage: Codable, Identifiable {
    var name: String
    var path: String
    var sessions: Int
    var turns: Int
    var tokens: Int = 0
    var id: String { path }
}

struct RecentSession: Codable, Identifiable {
    var title: String
    var project: String
    var model: String
    var updatedAt: Date
    var id: String { title + project + "\(updatedAt.timeIntervalSince1970)" }
}

struct UsageSnapshot: Codable {
    var account: MuseAccount = MuseAccount()
    var modelID: String = "muse-wonder-1.0"

    var todaySessions: Int = 0
    var todayTurns: Int = 0
    var weekSessions: Int = 0
    var weekTurns: Int = 0
    var totalSessions: Int = 0
    var totalTurns: Int = 0
    var totalPrompts: Int = 0
    var activeDays: Int = 0
    var streakDays: Int = 0
    var projectCount: Int = 0
    var lastActivityAt: Date?

    // Tokens reais dos session.jsonl (payload.event.record.quantity)
    var todayTokens: Int = 0
    var weekTokens: Int = 0
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCachedTokens: Int = 0
    var totalReasoningTokens: Int = 0
    var totalLLMCalls: Int = 0

    // Allowance oficial (`muse usage --json`, fonte "mint") — Current + Weekly
    var tierName: String = ""
    var windowUsedPercent: Int = -1   // -1 = indisponível
    var windowResetsAt: Date?
    var weeklyUsedPercent: Int = -1
    var weeklyResetsAt: Date?
    var allowanceAvailable: Bool { windowUsedPercent >= 0 }
    var windowFraction: Double { min(1, max(0, Double(windowUsedPercent) / 100)) }
    var weeklyFraction: Double { min(1, max(0, Double(weeklyUsedPercent) / 100)) }
    var allowanceStatus: String {
        switch windowUsedPercent {
        case ..<50: return "Tranquilo"
        case ..<75: return "Moderado"
        case ..<90: return "Alto"
        case ..<100: return "Quase no limite"
        default: return allowanceAvailable ? "No limite" : "—"
        }
    }

    var totalTokens: Int { totalInputTokens + totalOutputTokens }
    var uncachedInputTokens: Int { max(0, totalInputTokens - totalCachedTokens) }
    var cacheShare: Double {
        totalInputTokens > 0 ? Double(totalCachedTokens) / Double(totalInputTokens) : 0
    }

    var last7Days: [DayUsage] = []
    var topProjects: [ProjectUsage] = []
    var recentSessions: [RecentSession] = []
    var updatedAt: Date = Date()
    var isDemo: Bool = true

    var avgTurnsPerSession: Double {
        totalSessions > 0 ? Double(totalTurns) / Double(totalSessions) : 0
    }
    var busiestDayTurns: Int { last7Days.map(\.turns).max() ?? 0 }
    var statusText: String {
        if !account.isLoggedIn { return "Sem login" }
        return account.subscriptionActive ? "Assinatura ativa" : "Conectado"
    }

    static var demo: UsageSnapshot {
        let cal = Calendar.current
        let sessionsPerDay = [3, 5, 4, 7, 6, 2, 4]
        let days: [DayUsage] = (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let n = sessionsPerDay[6 - offset]
            return DayUsage(date: d, sessions: n, turns: n * 6)
        }
        var s = UsageSnapshot()
        s.account = MuseAccount(name: "Sua conta Meta", email: "voce@exemplo.com",
                                  provider: "meta", subscriptionActive: true)
        s.tierName = "Muse Code High Usage"
        s.windowUsedPercent = 22; s.windowResetsAt = Date().addingTimeInterval(3.5 * 3600)
        s.weeklyUsedPercent = 7; s.weeklyResetsAt = Date().addingTimeInterval(6 * 24 * 3600 + 9 * 3600)
        s.todaySessions = 4; s.todayTurns = 26
        s.weekSessions = 31; s.weekTurns = 186
        s.totalSessions = 148; s.totalTurns = 912; s.totalPrompts = 860
        s.activeDays = 22; s.streakDays = 5; s.projectCount = 6
        s.todayTokens = 842_000; s.weekTokens = 5_900_000
        s.totalInputTokens = 24_100_000; s.totalOutputTokens = 295_000
        s.totalCachedTokens = 22_000_000; s.totalReasoningTokens = 159_000
        s.totalLLMCalls = 763
        s.lastActivityAt = Date()
        s.last7Days = days
        s.topProjects = [
            ProjectUsage(name: "muse_stats", path: "~/Developer/muse_stats", sessions: 18, turns: 120),
            ProjectUsage(name: "capturame", path: "~/Sites/capturame", sessions: 12, turns: 74),
            ProjectUsage(name: "api-gateway", path: "~/Sites/api-gateway", sessions: 9, turns: 51),
        ]
        s.recentSessions = [
            RecentSession(title: "Monitor de uso do Muse", project: "muse_stats", model: "muse-wonder-1.0", updatedAt: Date()),
            RecentSession(title: "Ajustes de layout", project: "capturame", model: "muse-wonder-1.0", updatedAt: Date().addingTimeInterval(-3600)),
        ]
        s.isDemo = true
        return s
    }
}

// MARK: - Formatação

enum Fmt {
    static func count(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(n) / 1_000)
        default: return "\(n)"
        }
    }
    static func countdown(to date: Date?) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(date.timeIntervalSinceNow))
        let h = s / 3600, m = (s % 3600) / 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        return "\(h)h \(String(format: "%02d", m))m"
    }
    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(Date().timeIntervalSince(date)))
        switch s {
        case ..<60: return "agora"
        case ..<3600: return "há \(s / 60) min"
        case ..<86400: return "há \(s / 3600)h"
        default: return "há \(s / 86400)d"
        }
    }
}
