import Foundation

/// Qual conta o Claude Code deste Mac está usando, para o subtítulo do painel ("Pessoal · Max", "Team · Empresa").
/// Lê só o `oauthAccount` do `~/.claude.json` (sem token nenhum).
enum Conta {
    private static let planos = [
        "claude_max": "Max", "claude_pro": "Pro", "claude_team": "Team", "claude_enterprise": "Enterprise",
    ]

    static func descricao() -> String {
        guard let conta = lerConta() else { return "Conta do Claude Code" }
        return descricao(tipo: conta["organizationType"] as? String, organizacao: conta["organizationName"] as? String)
    }

    static func descricao(tipo: String?, organizacao: String?) -> String {
        guard let tipo, let plano = planos[tipo] else { return "Conta do Claude Code" }
        if tipo == "claude_team" || tipo == "claude_enterprise" {
            return [plano, organizacao].compactMap { $0 }.joined(separator: " · ")
        }
        return "Pessoal · \(plano)"
    }

    private static func lerConta() -> [String: Any]? {
        let casa = FileManager.default.homeDirectoryForCurrentUser
        let config = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
        let candidatos = [config?.appendingPathComponent(".claude.json"), casa.appendingPathComponent(".claude.json")]
        for arquivo in candidatos.compactMap({ $0 }) {
            if let dados = try? Data(contentsOf: arquivo),
               let json = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
               let conta = json["oauthAccount"] as? [String: Any] {
                return conta
            }
        }
        return nil
    }
}
