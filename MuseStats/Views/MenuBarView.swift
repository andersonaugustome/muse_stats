import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Ring(fraction: s.windowFraction, percent: s.windowUsedPercent, size: 72, lineWidth: 8, caption: "atual")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly: \(s.weeklyUsedPercent >= 0 ? "\(s.weeklyUsedPercent)%" : "—")")
                        .font(.headline)
                    Text("Semana reseta em \(Fmt.countdown(to: s.weeklyResetsAt))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Janela reseta em \(Fmt.countdown(to: s.windowResetsAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Muse.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Muse · \(s.modelID)").font(.headline).lineLimit(1)
                    Text(s.account.subscriptionActive ? "Assinatura ativa" : "Conectado")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Última atividade \(Fmt.relative(s.lastActivityAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            LabeledContent("Hoje", value: "\(s.todaySessions) sessões · \(s.todayTurns) turnos")
            LabeledContent("Tokens hoje", value: Fmt.count(s.todayTokens))
            LabeledContent("Tokens total", value: "\(Fmt.count(s.totalTokens)) · \(s.totalLLMCalls) chamadas")
            LabeledContent("Semana", value: "\(s.weekSessions) sessões · \(s.weekTurns) turnos")
            LabeledContent("Sequência", value: "\(s.streakDays) dias")
            Divider()
            HStack {
                Button("Atualizar") { Task { await store.refresh() } }
                Spacer()
                Button("Abrir dashboard") { NSApp.activate(ignoringOtherApps: true) }
                    .buttonStyle(.borderedProminent).tint(Muse.accent)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = store.snapshot
        VStack(alignment: .leading, spacing: 16) {
            Text("Conta e dados").font(.title3.weight(.bold))
            LabeledContent("Conta", value: s.account.email.isEmpty ? "—" : s.account.email)
            LabeledContent("Assinatura", value: s.statusText)
            LabeledContent("Modelo", value: s.modelID)
            Divider()
            Text("Fontes locais (somente leitura):\n• ~/.local/share/muse/session-index.db — sessões, turnos, projetos\n• ~/.config/muse/auth.json — nome, email e status da assinatura\n\nO token de acesso nunca é lido, exibido ou enviado para fora. A Meta não publica um limite numérico da assinatura do Muse, então o app mostra atividade real em vez de uma porcentagem estimada.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Fechar") { dismiss() }.buttonStyle(.borderedProminent).tint(Muse.accent) }
        }
        .padding(22).frame(width: 480)
    }
}
