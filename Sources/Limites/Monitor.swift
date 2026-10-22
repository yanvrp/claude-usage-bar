import AppKit
import Foundation
import ServiceManagement
import UserNotifications

/// Faixa de uso: decide a cor do ícone, das barras e quando avisar.
enum Faixa: Comparable {
    case tranquila, atencao, critica

    init(_ percentual: Double) {
        self = percentual >= 95 ? .critica : percentual >= 80 ? .atencao : .tranquila
    }
}

/// Estado do app: consulta a cada 2 minutos (e ao acordar o Mac), guarda o último dado bom e avisa em 80% e 95%.
@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var janelas: [Janela] = []
    @Published private(set) var atualizadoEm: Date?
    @Published private(set) var conta = Conta.descricao()
    @Published private(set) var erro: String?
    @Published private(set) var consultando = false
    @Published var abrirAoIniciar = SMAppService.mainApp.status == .enabled {
        didSet { alternarAberturaAoIniciar() }
    }

    private static let intervalo: TimeInterval = 120
    /// Depois de um "muitas consultas" (429), a próxima consulta só sai depois disto.
    private var pausaAte = Date.distantPast
    private var relogio: Timer?

    /// Maior faixa entre as janelas; sem dado, o ícone fica cinza.
    var faixa: Faixa? { janelas.map { Faixa($0.percentual) }.max() }

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        relogio = Timer.scheduledTimer(withTimeInterval: Self.intervalo, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.atualizar() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.atualizar() } }
        Task { await atualizar() }
    }

    func atualizar() async {
        guard !consultando, Date() >= pausaAte else { return }
        consultando = true
        defer { consultando = false }
        do {
            janelas = try await ConsultaUso.buscar()
            conta = Conta.descricao()
            atualizadoEm = Date()
            erro = nil
            avisarSePreciso()
        } catch {
            if case ErroUso.http(429) = error { pausaAte = Date().addingTimeInterval(600) }
            // Mantém o último dado bom na tela e explica o que houve.
            self.erro = (error as? LocalizedError)?.errorDescription ?? "Sem conexão com a Anthropic. Tento de novo em 2 minutos."
        }
    }

    /// Um aviso por janela e por faixa até o reset (a chave inclui o horário do reset).
    private func avisarSePreciso() {
        let feitos = UserDefaults.standard
        for janela in janelas {
            let faixa = Faixa(janela.percentual)
            guard faixa != .tranquila else { continue }
            let reset = janela.resetaEm.map { String(Int($0.timeIntervalSince1970)) } ?? "sem-reset"
            let chave = "aviso.\(janela.id).\(reset).\(faixa == .critica ? 95 : 80)"
            guard !feitos.bool(forKey: chave) else { continue }
            feitos.set(true, forKey: chave)

            let conteudo = UNMutableNotificationContent()
            conteudo.title = "Claude: \(janela.nome) em \(Int(janela.percentual.rounded()))%"
            conteudo.body = janela.resetaEm.map { "Reseta \(Formato.reset($0))." } ?? "Perto do limite."
            conteudo.sound = faixa == .critica ? .default : nil
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: chave, content: conteudo, trigger: nil))
        }
    }

    private func alternarAberturaAoIniciar() {
        do {
            if abrirAoIniciar { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            erro = "Não consegui mudar o \"Abrir ao iniciar\". Confira em Ajustes do Sistema › Geral › Itens de Início."
        }
    }
}

enum Formato {
    /// "hoje 21:10", "amanhã 09:00" ou "sáb 23:00".
    static func reset(_ data: Date) -> String {
        let cal = Calendar.current
        let hora = data.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if cal.isDateInToday(data) { return "hoje \(hora)" }
        if cal.isDateInTomorrow(data) { return "amanhã \(hora)" }
        let dia = data.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR")))
        return "\(dia.replacingOccurrences(of: ".", with: "")) \(hora)"
    }

    /// "em 2 h 10 min" ou "em 35 min" até o reset.
    static func falta(_ data: Date, agora: Date) -> String {
        let minutos = max(Int(data.timeIntervalSince(agora) / 60), 0)
        if minutos < 60 { return "em \(minutos) min" }
        let horas = minutos / 60
        if horas < 24 { return minutos % 60 == 0 ? "em \(horas) h" : "em \(horas) h \(minutos % 60)" }
        return "em \(horas / 24) d \(horas % 24) h"
    }

    static func atualizado(_ data: Date, agora: Date) -> String {
        let minutos = Int(agora.timeIntervalSince(data) / 60)
        return minutos < 1 ? "atualizado agora" : "atualizado há \(minutos) min"
    }
}
