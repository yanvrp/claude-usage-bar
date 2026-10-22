import Foundation
import Testing
@testable import Limites

@Test func interpretaJanelasConhecidasPorModeloENulas() throws {
    let json = """
    {"five_hour":{"utilization":6.0,"resets_at":"2026-10-21T21:10:00.123+00:00"},
     "seven_day":{"utilization":32,"resets_at":"2026-10-24T23:00:00+00:00"},
     "seven_day_opus":null,
     "seven_day_sonnet":{"utilization":0,"resets_at":null},
     "extra_usage":{"is_enabled":false},
     "model_scoped":[{"display_name":"Fable","utilization":0,"resets_at":"2026-10-24T23:00:00Z"}]}
    """
    let janelas = try ConsultaUso.interpretar(Data(json.utf8))
    #expect(janelas.map(\.nome) == ["5 horas", "Semana", "Fable · semana", "Sonnet · semana"])
    #expect(janelas[0].percentual == 6)
    #expect(janelas[0].resetaEm != nil)
    #expect(janelas[3].resetaEm == nil)
}

@Test func descricaoDaConta() {
    #expect(Conta.descricao(tipo: "claude_max", organizacao: "fulano's Organization") == "Pessoal · Max")
    #expect(Conta.descricao(tipo: "claude_pro", organizacao: nil) == "Pessoal · Pro")
    #expect(Conta.descricao(tipo: "claude_team", organizacao: "Minha Empresa") == "Team · Minha Empresa")
    #expect(Conta.descricao(tipo: "algo_novo", organizacao: "X") == "Conta do Claude Code")
}

@Test func faixas() {
    #expect(Faixa(79.9) == .tranquila)
    #expect(Faixa(80) == .atencao)
    #expect(Faixa(95) == .critica)
}
