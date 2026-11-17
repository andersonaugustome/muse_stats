import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showSettings = false

    var body: some View {
        let s = store.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(s)
                HStack(alignment: .top, spacing: 20) {
                    currentCard(s).frame(width: 300)
                    weeklyCard(s)
                }
                HStack(spacing: 20) {
                    StatTile(icon: "terminal.fill", value: "\(s.todaySessions)", label: "Sessões hoje")
                    StatTile(icon: "arrow.triangle.2.circlepath", value: "\(s.todayTurns)", label: "Turnos hoje")
                    StatTile(icon: "calendar.badge.clock", value: "\(s.weekSessions)", label: "Sessões na semana")
                    StatTile(icon: "flame.fill", value: "\(s.streakDays) dias", label: "Sequência ativa")
                }
                HStack(spacing: 20) {
                    StatTile(icon: "number", value: Fmt.count(s.todayTokens), label: "Tokens hoje")
                    StatTile(icon: "calendar", value: Fmt.count(s.weekTokens), label: "Tokens na semana")
                    StatTile(icon: "square.stack.3d.up.fill", value: Fmt.count(s.totalTokens), label: "Tokens no total (in + out)")
                    StatTile(icon: "cpu", value: Fmt.count(s.totalLLMCalls), label: "Chamadas ao modelo")
                }
                HStack(alignment: .top, spacing: 20) {
                    accountCard(s).frame(width: 300)
                    VStack(spacing: 20) { weekCard(s); totalsRow(s) }
                }
                HStack(alignment: .top, spacing: 20) {
                    projectsCard(s)
                    recentCard(s)
                }
                footer(s)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store) }
    }

    private func header(_ s: UsageSnapshot) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Muse.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Muse da Meta").font(.system(size: 24, weight: .bold, design: .rounded))
                Text("\(s.tierName.isEmpty ? s.modelID : s.tierName) · última atividade \(Fmt.relative(s.lastActivityAt))")
                    .font(.subheadline).foregroundStyle(Muse.sub)
            }
            if s.isDemo {
                Text("DEMO").font(.caption2.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Muse.accentSoft, in: Capsule()).foregroundStyle(Muse.accent)
            }
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise").rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
            }.buttonStyle(.bordered).controlSize(.large).help("Atualizar")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.bordered).controlSize(.large).help("Ajustes")
        }
    }

    private func currentCard(_ s: UsageSnapshot) -> some View {
        Card {
            VStack(spacing: 14) {
                Text("Current usage").font(.subheadline.weight(.semibold))
                Ring(fraction: s.windowFraction, percent: s.windowUsedPercent)
                VStack(spacing: 4) {
                    Text(s.allowanceAvailable ? s.allowanceStatus : "Indisponível")
                        .font(.subheadline.weight(.semibold))
                    Text("Reseta em \(Fmt.countdown(to: s.windowResetsAt))")
                        .font(.caption).foregroundStyle(Muse.sub)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func weeklyCard(_ s: UsageSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Weekly limit").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(s.tierName.isEmpty ? "Muse" : s.tierName)
                        .font(.caption).foregroundStyle(Muse.sub)
                }
                UsageBar(title: "Semana", percent: s.weeklyUsedPercent, fraction: s.weeklyFraction,
                         resetsIn: Fmt.countdown(to: s.weeklyResetsAt))
                UsageBar(title: "Janela atual", percent: s.windowUsedPercent, fraction: s.windowFraction,
                         resetsIn: Fmt.countdown(to: s.windowResetsAt))
                Divider()
                HStack(spacing: 16) {
                    Label("\(Fmt.count(s.todayTokens)) tokens hoje", systemImage: "number")
                    Label("\(s.todaySessions) sessões hoje", systemImage: "terminal")
                    Spacer()
                    Text("Fonte: muse usage").font(.caption2).foregroundStyle(Muse.sub)
                }.font(.caption).foregroundStyle(Muse.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func accountCard(_ s: UsageSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(Muse.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.account.name.isEmpty ? "Conta Meta" : s.account.name)
                            .font(.headline).lineLimit(1)
                        Text(s.account.email.isEmpty ? "Muse" : s.account.email)
                            .font(.caption).foregroundStyle(Muse.sub).lineLimit(1)
                    }
                }
                Divider()
                LabeledContent("Assinatura") {
                    Text(s.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(s.account.subscriptionActive ? .green : .secondary)
                }
                LabeledContent("Provedor", value: s.account.provider.capitalized)
                LabeledContent("Modelo", value: s.modelID)
                LabeledContent("Dias ativos", value: "\(s.activeDays)")
                Divider()
                LabeledContent("Entrada", value: "\(Fmt.count(s.totalInputTokens)) tokens")
                LabeledContent("Saída", value: "\(Fmt.count(s.totalOutputTokens)) tokens")
                LabeledContent("Cache", value: "\(Fmt.count(s.totalCachedTokens)) (\(Int(s.cacheShare * 100))%)")
                LabeledContent("Raciocínio", value: "\(Fmt.count(s.totalReasoningTokens)) tokens")
                Text("Login reutilizado do Muse nesta máquina. Nenhuma senha é pedida e o token nunca é lido.")
                    .font(.caption2).foregroundStyle(Muse.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weekCard(_ s: UsageSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Últimos 7 dias").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(s.weekTurns) turnos").font(.caption).foregroundStyle(Muse.sub)
                }
                WeekChart(days: s.last7Days)
            }
        }
    }

    private func totalsRow(_ s: UsageSnapshot) -> some View {
        HStack(spacing: 20) {
            StatTile(icon: "square.stack.3d.up.fill", value: Fmt.count(s.totalSessions), label: "Sessões no total")
            StatTile(icon: "arrow.triangle.2.circlepath", value: Fmt.count(s.totalTurns), label: "Turnos no total")
            StatTile(icon: "folder.fill", value: "\(s.projectCount)", label: "Projetos")
            StatTile(icon: "gauge.medium", value: String(format: "%.1f", s.avgTurnsPerSession), label: "Turnos / sessão")
        }
    }

    private func projectsCard(_ s: UsageSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Projetos mais ativos").font(.subheadline.weight(.semibold))
                if s.topProjects.isEmpty {
                    Text("Nenhum projeto ainda.").font(.caption).foregroundStyle(Muse.sub)
                }
                ForEach(s.topProjects) { project in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Muse.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(.subheadline)
                            Text(project.path).font(.caption2).foregroundStyle(Muse.sub).lineLimit(1)
                        }
                        Spacer()
                        Text("\(Fmt.count(project.tokens)) tok").font(.caption).foregroundStyle(Muse.sub)
                        Text("\(project.turns) turnos").font(.caption).foregroundStyle(Muse.sub)
                        Text("\(project.sessions)").font(.caption.weight(.semibold)).frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func recentCard(_ s: UsageSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sessões recentes").font(.subheadline.weight(.semibold))
                if s.recentSessions.isEmpty {
                    Text("Nenhuma sessão recente.").font(.caption).foregroundStyle(Muse.sub)
                }
                ForEach(s.recentSessions.prefix(4)) { session in
                    HStack(spacing: 10) {
                        Image(systemName: "text.bubble.fill").foregroundStyle(Muse.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.title).font(.subheadline).lineLimit(1)
                            Text(session.project).font(.caption2).foregroundStyle(Muse.sub).lineLimit(1)
                        }
                        Spacer()
                        Text(Fmt.relative(session.updatedAt)).font(.caption2).foregroundStyle(Muse.sub)
                    }
                }
            }
        }
    }

    private func footer(_ s: UsageSnapshot) -> some View {
        Text("Atualizado \(s.updatedAt, format: .dateTime.hour().minute()) · Fonte: ~/.local/share/muse/session-index.db + ~/.config/muse/auth.json\(s.isDemo ? " (demo — Muse não encontrado)" : "") · A Meta não publica limite numérico da assinatura, por isso não exibimos % fictícia.")
            .font(.caption2).foregroundStyle(Muse.sub)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }
}
