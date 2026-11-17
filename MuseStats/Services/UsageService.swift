import Foundation
import SQLite3

/// Lê o uso real do Muse (Meta) nesta máquina:
/// - Conta/login: `~/.config/muse/auth.json` (só metadados: nome, email, assinatura —
///   o token/credencial nunca é lido nem sai do app).
/// - Atividade: `~/.local/share/muse/session-index.db` (índice SQLite do próprio Muse).
/// Sem esses arquivos, retorna demonstração — a UI nunca fica vazia.
enum UsageService {

    static func load() async -> UsageSnapshot {
        await Task.detached(priority: .utility) { scan() }.value
    }

    private static func scan() -> UsageSnapshot {
        var snap = scanLocal()
        applyAllowance(&snap)
        return snap
    }

    /// Current usage + Weekly limit oficiais: `muse usage --json` (sem turno de modelo,
    /// reutiliza o login já salvo pelo Muse). Falha silenciosa => -1 (UI mostra local).
    private static func applyAllowance(_ snap: inout UsageSnapshot) {
        let fm = FileManager.default
        let candidates = [
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/muse").path,
            "/opt/homebrew/bin/muse", "/usr/local/bin/muse",
        ]
        guard let exe = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = ["usage", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            if process.isRunning { process.terminate() }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let allowance = root["allowance"] as? [String: Any] else { return }

        snap.tierName = allowance["tier"] as? String ?? snap.tierName
        if let w = allowance["window"] as? [String: Any] {
            snap.windowUsedPercent = w["usedPercent"] as? Int ?? snap.windowUsedPercent
            if let ms = w["resetsAtMs"] as? Double {
                snap.windowResetsAt = Date(timeIntervalSince1970: ms / 1000)
            }
        }
        if let w = allowance["weekly"] as? [String: Any] {
            snap.weeklyUsedPercent = w["usedPercent"] as? Int ?? snap.weeklyUsedPercent
            if let ms = w["resetsAtMs"] as? Double {
                snap.weeklyResetsAt = Date(timeIntervalSince1970: ms / 1000)
            }
        }
    }

    private static func scanLocal() -> UsageSnapshot {
        let account = readAccount()
        guard let dbPath = prepareDatabaseCopy() else {
            var demo = UsageSnapshot.demo
            demo.account = account.isLoggedIn ? account : demo.account
            demo.isDemo = true
            return demo
        }
        defer { try? FileManager.default.removeItem(at: dbPath.deletingLastPathComponent()) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return UsageSnapshot.demo
        }
        defer { sqlite3_close(db) }

        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today) ?? today

        func epoch(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970) * 1_000_000 }
        func intQuery(_ sql: String, bind: Int64? = nil) -> Int {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
            defer { sqlite3_finalize(stmt) }
            if let bind { sqlite3_bind_int64(stmt, 1, bind) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        }

        // turns por sessão: msp_turn_count quando existe, senão prompt_count
        let turns = "CASE WHEN coalesce(msp_turn_count,0) > 0 THEN msp_turn_count ELSE coalesce(prompt_count,0) END"

        var snap = UsageSnapshot(account: account, isDemo: false)
        snap.totalSessions = intQuery("SELECT count(*) FROM sessions")
        guard snap.totalSessions > 0 else { return UsageSnapshot.demo }
        snap.totalTurns = intQuery("SELECT coalesce(sum(\(turns)),0) FROM sessions")
        snap.totalPrompts = intQuery("SELECT coalesce(sum(prompt_count),0) FROM sessions")
        snap.todaySessions = intQuery("SELECT count(*) FROM sessions WHERE created_at_us >= ?1", bind: epoch(today))
        snap.todayTurns = intQuery("SELECT coalesce(sum(\(turns)),0) FROM sessions WHERE created_at_us >= ?1", bind: epoch(today))
        snap.weekSessions = intQuery("SELECT count(*) FROM sessions WHERE created_at_us >= ?1", bind: epoch(weekAgo))
        snap.weekTurns = intQuery("SELECT coalesce(sum(\(turns)),0) FROM sessions WHERE created_at_us >= ?1", bind: epoch(weekAgo))
        snap.projectCount = intQuery("SELECT count(DISTINCT workspace_root) FROM sessions WHERE workspace_root IS NOT NULL AND workspace_root != ''")

        // Modelo predominante (msp_model_id tem precedência no índice novo)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT coalesce(nullif(msp_model_id,''), model_id, '') m, count(*) n FROM sessions GROUP BY m ORDER BY n DESC LIMIT 1", -1, &stmt, nil) == SQLITE_OK, let stmt {
            if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
                snap.modelID = String(cString: c)
            }
            sqlite3_finalize(stmt)
        }
        let lastUs = intQuery("SELECT coalesce(max(updated_at_us),0) FROM sessions")
        snap.lastActivityAt = lastUs > 0 ? Date(timeIntervalSince1970: Double(lastUs) / 1_000_000) : nil

        // Últimos 7 dias + dias ativos + sequência
        var perDay: [Date: (sessions: Int, turns: Int)] = [:]
        if sqlite3_prepare_v2(db, "SELECT created_at_us, \(turns) FROM sessions WHERE created_at_us IS NOT NULL", -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)) / 1_000_000)
                let day = cal.startOfDay(for: date)
                perDay[day, default: (0, 0)].sessions += 1
                perDay[day, default: (0, 0)].turns += Int(sqlite3_column_int64(stmt, 1))
            }
            sqlite3_finalize(stmt)
        }
        snap.activeDays = perDay.count
        snap.last7Days = (0..<7).reversed().map { offset in
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: now) ?? now)
            let v = perDay[day] ?? (0, 0)
            return DayUsage(date: day, sessions: v.sessions, turns: v.turns)
        }
        var streak = 0
        var cursor = today
        if perDay[cursor] == nil { cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        while perDay[cursor] != nil { streak += 1; cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        snap.streakDays = streak

        // Projetos
        if sqlite3_prepare_v2(db, "SELECT coalesce(workspace_root,''), count(*), coalesce(sum(\(turns)),0) FROM sessions GROUP BY 1 ORDER BY 2 DESC LIMIT 4", -1, &stmt, nil) == SQLITE_OK, let stmt {
            var projects: [ProjectUsage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                guard !path.isEmpty else { continue }
                projects.append(ProjectUsage(
                    name: (path as NSString).lastPathComponent,
                    path: (path as NSString).abbreviatingWithTildeInPath,
                    sessions: Int(sqlite3_column_int64(stmt, 1)),
                    turns: Int(sqlite3_column_int64(stmt, 2))))
            }
            snap.topProjects = projects
            sqlite3_finalize(stmt)
        }

        // Sessões recentes (título gerado pelo próprio Muse)
        if sqlite3_prepare_v2(db, "SELECT coalesce(nullif(session_name,''), nullif(msp_title,''), title), coalesce(workspace_root,''), coalesce(nullif(msp_model_id,''), model_id, ''), coalesce(updated_at_us, created_at_us, 0) FROM sessions ORDER BY updated_at_us DESC LIMIT 5", -1, &stmt, nil) == SQLITE_OK, let stmt {
            var recent: [RecentSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let title = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "Sessão"
                let path = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                let model = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let us = sqlite3_column_int64(stmt, 3)
                recent.append(RecentSession(
                    title: String(title.prefix(60)),
                    project: (path as NSString).lastPathComponent,
                    model: model,
                    updatedAt: Date(timeIntervalSince1970: Double(us) / 1_000_000)))
            }
            snap.recentSessions = recent
            sqlite3_finalize(stmt)
        }

        // Tokens: session_log_path (SQLite) -> projeto, p/ atribuir tokens por projeto
        var projectByLog: [String: String] = [:]
        if sqlite3_prepare_v2(db, "SELECT session_log_path, coalesce(workspace_root,'') FROM sessions", -1, &stmt, nil) == SQLITE_OK, let stmt {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let log = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let ws = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                if !log.isEmpty { projectByLog[log] = (ws as NSString).lastPathComponent }
            }
            sqlite3_finalize(stmt)
        }
        let byProject = scanTokens(into: &snap, projectByLog: projectByLog, calendar: cal, today: today, weekAgo: weekAgo)
        snap.topProjects = snap.topProjects.map { project in
            var p = project
            p.tokens = byProject[project.name] ?? 0
            return p
        }

        snap.updatedAt = now
        return snap
    }

    /// Soma tokens reais de `payload.event.record.quantity` nos session.jsonl.
    private static func scanTokens(into snap: inout UsageSnapshot, projectByLog: [String: String],
                                   calendar cal: Calendar, today: Date, weekAgo: Date) -> [String: Int] {
        var tokensByProject: [String: Int] = [:]
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/muse/sessions", isDirectory: true)
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }

        var tokensByDay: [Date: Int] = [:]
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "session.jsonl",
                  !url.path.contains(".msp-view"),
                  let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let project = projectByLog[url.path] ?? ""
            for line in content.split(separator: "\n") {
                guard line.contains("\"input_tokens\""),
                      let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      let event = payload["event"] as? [String: Any],
                      let record = event["record"] as? [String: Any],
                      let q = record["quantity"] as? [String: Any],
                      let input = q["input_tokens"] as? Int else { continue }

                let output = q["output_tokens"] as? Int ?? 0
                let total = input + output
                snap.totalInputTokens += input
                snap.totalOutputTokens += output
                snap.totalCachedTokens += q["cached_tokens"] as? Int ?? 0
                snap.totalReasoningTokens += q["reasoning_tokens"] as? Int ?? 0
                snap.totalLLMCalls += 1
                if !project.isEmpty { tokensByProject[project, default: 0] += total }

                let us = obj["recorded_at"] as? Int64 ?? 0
                guard us > 0 else { continue }
                let date = Date(timeIntervalSince1970: Double(us) / 1_000_000)
                let day = cal.startOfDay(for: date)
                tokensByDay[day, default: 0] += total
                if day == today { snap.todayTokens += total }
                if date >= weekAgo { snap.weekTokens += total }
            }
        }
        snap.last7Days = snap.last7Days.map { day in
            var d = day
            d.tokens = tokensByDay[cal.startOfDay(for: day.date)] ?? 0
            return d
        }
        return tokensByProject
    }

    // Copia db+wal+shm para temp: abrir o original readonly com WAL ativo pode falhar.
    private static func prepareDatabaseCopy() -> URL? {
        let fm = FileManager.default
        let src = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/muse/session-index.db")
        guard fm.fileExists(atPath: src.path) else { return nil }
        let dir = fm.temporaryDirectory.appendingPathComponent("musestats-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: src.path + suffix)
                if fm.fileExists(atPath: from.path) {
                    try fm.copyItem(at: from, to: dir.appendingPathComponent(from.lastPathComponent))
                }
            }
            return dir.appendingPathComponent("session-index.db")
        } catch { return nil }
    }

    private static func readAccount() -> MuseAccount {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/muse/auth.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any],
              let meta = providers["meta"] as? [String: Any] else { return MuseAccount() }
        return MuseAccount(
            name: meta["user_full_name"] as? String ?? "",
            email: meta["user_email"] as? String ?? "",
            provider: "meta",
            subscriptionActive: meta["subs_active"] as? Bool ?? false,
            apiBaseURL: meta["api_base_url"] as? String ?? "")
    }
}
