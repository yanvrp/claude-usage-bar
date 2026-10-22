import Foundation
import OSLog

/// Uma janela de limite da assinatura (5 horas, semana, por modelo...), como o `/usage` do Claude Code mostra.
struct Janela: Identifiable, Equatable {
    let id: String
    let nome: String
    /// 0 a 100.
    let percentual: Double
    let resetaEm: Date?
    /// Duração da janela (5 h ou 7 dias): com o reset, diz quanto do tempo já passou.
    let duracao: TimeInterval

    /// Fração do tempo da janela que já passou (0 a 1), ou nil sem horário de reset.
    func tempoPassado(agora: Date) -> Double? {
        guard let resetaEm else { return nil }
        return min(max(1 - resetaEm.timeIntervalSince(agora) / duracao, 0), 1)
    }
}

enum ErroUso: LocalizedError {
    case semLogin
    case semClaudeCode
    case tokenVencido
    case http(Int)
    case resposta

    var errorDescription: String? {
        switch self {
        case .semLogin: "Não achei o login do Claude Code neste Mac. Rode `claude` no terminal, entre na conta e clique em Atualizar."
        case .semClaudeCode: "Não achei o Claude Code de terminal para renovar o login. Confira se o comando `claude` está instalado."
        case .tokenVencido, .http(401), .http(403):
            "Não consegui renovar o login do Claude Code. Rode `claude` no terminal uma vez e clique em Atualizar."
        case .http(429): "A Anthropic pediu uma pausa nas consultas. Tento de novo em 10 minutos."
        case .http(let codigo): "A consulta de uso respondeu com erro \(codigo). Tento de novo na próxima atualização."
        case .resposta: "A resposta de uso veio num formato que não reconheço."
        }
    }
}

/// Lê o uso da assinatura pela mesma consulta que o `/usage` do Claude Code faz, com o login que o Claude Code de
/// terminal guarda no Chaveiro. O app não mexe em token: quando o login vence, pede ao próprio Claude Code para
/// renová-lo (um `claude -p` mínimo). Token lido a cada consulta, só em memória, nunca gravado nem registrado.
enum ConsultaUso {
    private static let log = Logger(subsystem: "dev.yanrockenback.limites", category: "uso")
    private static let endereco = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Nomes em português das janelas conhecidas; janela nova que a Anthropic criar entra com o nome dela.
    private static let nomes: [String: String] = [
        "five_hour": "5 horas",
        "seven_day": "Semana",
        "seven_day_opus": "Opus · semana",
        "seven_day_sonnet": "Sonnet · semana",
        "seven_day_oauth_apps": "Apps conectados · semana",
        "seven_day_cowork": "Cowork · semana",
    ]
    private static let ordem = ["five_hour", "seven_day"]

    static func buscar() async throws -> [Janela] {
        let token: String
        do {
            token = try lerToken()
        } catch ErroUso.tokenVencido {
            try await renovarPeloClaudeCode()
            token = try lerToken()
        }
        do {
            return try await consultar(token)
        } catch ErroUso.http(401) {
            // Token recusado antes da hora (revogado ou trocado): uma renovação e uma nova tentativa.
            try await renovarPeloClaudeCode()
            return try await consultar(try lerToken())
        }
    }

    private static func consultar(_ token: String) async throws -> [Janela] {
        var pedido = URLRequest(url: endereco, timeoutInterval: 20)
        pedido.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        pedido.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        pedido.setValue("application/json", forHTTPHeaderField: "Accept")

        let inicio = Date()
        let (dados, resposta) = try await URLSession.shared.data(for: pedido)
        let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int(Date().timeIntervalSince(inicio) * 1000)
        guard status == 200 else {
            log.notice("[limites] \(ms)ms status=\(status)")
            throw ErroUso.http(status)
        }
        let janelas = try interpretar(dados)
        log.notice("[limites] \(ms)ms status=200 janelas=\(janelas.count)")
        return janelas
    }

    /// Pega o login que o Claude Code de terminal guarda no Chaveiro, pela ferramenta `security` do macOS
    /// (o "Sempre permitir" do aviso do Chaveiro vale para ela e não se perde a cada nova versão do app).
    private static func lerToken() throws -> String {
        let (codigo, dados) = try rodar(URL(fileURLWithPath: "/usr/bin/security"),
                                        ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        guard codigo == 0,
              let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw ErroUso.semLogin }
        // Margem de 2 minutos para não consultar com um token que vence no meio do caminho.
        if let expira = oauth["expiresAt"] as? Double, Date(timeIntervalSince1970: expira / 1000 - 120) < Date() {
            throw ErroUso.tokenVencido
        }
        return token
    }

    /// O app de desktop do Claude não renova este login; só o Claude Code de terminal renova, ao ser usado.
    /// Uma pergunta mínima no modelo mais barato, numa pasta temporária e sem salvar sessão, faz ele renovar
    /// e gravar no Chaveiro do jeito oficial.
    private static func renovarPeloClaudeCode() async throws {
        let casa = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatos = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(casa)/.local/bin/claude", "\(casa)/.claude/local/claude"]
        guard let claude = candidatos.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ErroUso.semClaudeCode
        }
        let inicio = Date()
        let (codigo, _) = try await Task.detached {
            try rodar(URL(fileURLWithPath: claude),
                      ["-p", "Responda só: ok", "--model", "haiku", "--no-session-persistence"],
                      pasta: FileManager.default.temporaryDirectory)
        }.value
        log.notice("[limites] renovacao \(Int(Date().timeIntervalSince(inicio) * 1000))ms saida=\(codigo)")
        if codigo != 0 { throw ErroUso.tokenVencido }
    }

    /// Roda um programa e devolve o código de saída e o que ele escreveu (o stderr é descartado).
    private static func rodar(_ programa: URL, _ argumentos: [String], pasta: URL? = nil) throws -> (Int32, Data) {
        let processo = Process()
        processo.executableURL = programa
        processo.arguments = argumentos
        if let pasta { processo.currentDirectoryURL = pasta }
        let saida = Pipe()
        processo.standardOutput = saida
        processo.standardError = FileHandle.nullDevice
        processo.standardInput = FileHandle.nullDevice
        try processo.run()
        let dados = saida.fileHandleForReading.readDataToEndOfFile()
        processo.waitUntilExit()
        return (processo.terminationStatus, dados)
    }

    /// Toda chave com `utilization` vira uma janela; `model_scoped` traz as janelas por modelo (ex.: Fable).
    static func interpretar(_ dados: Data) throws -> [Janela] {
        guard let raiz = try JSONSerialization.jsonObject(with: dados) as? [String: Any] else { throw ErroUso.resposta }
        var janelas: [Janela] = []
        for (chave, valor) in raiz {
            guard let item = valor as? [String: Any], let janela = janela(id: chave, nome: nome(de: chave), item) else { continue }
            janelas.append(janela)
        }
        for item in raiz["model_scoped"] as? [[String: Any]] ?? [] {
            guard let rotulo = item["display_name"] as? String,
                  let janela = janela(id: "modelo:\(rotulo)", nome: "\(rotulo) · semana", item) else { continue }
            janelas.append(janela)
        }
        return janelas.sorted { a, b in
            let (ia, ib) = (ordem.firstIndex(of: a.id) ?? 99, ordem.firstIndex(of: b.id) ?? 99)
            return ia != ib ? ia < ib : a.nome < b.nome
        }
    }

    private static func janela(id: String, nome: String, _ item: [String: Any]) -> Janela? {
        guard let uso = (item["utilization"] as? NSNumber)?.doubleValue else { return nil }
        let duracao: TimeInterval = id == "five_hour" ? 5 * 3600 : 7 * 86_400
        return Janela(id: id, nome: nome, percentual: min(max(uso, 0), 100), resetaEm: data(item["resets_at"]), duracao: duracao)
    }

    private static func nome(de chave: String) -> String {
        nomes[chave] ?? chave.replacingOccurrences(of: "seven_day_", with: "")
            .replacingOccurrences(of: "_", with: " ").capitalized + " · semana"
    }

    private static func data(_ valor: Any?) -> Date? {
        guard let texto = valor as? String else { return nil }
        let comFracao = ISO8601DateFormatter()
        comFracao.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return comFracao.date(from: texto) ?? ISO8601DateFormatter().date(from: texto)
    }
}
