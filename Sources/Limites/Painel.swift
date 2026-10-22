import AppKit
import SwiftUI

extension Faixa {
    var cor: Color { Color(nsColor: corSistema) }

    var corSistema: NSColor {
        switch self {
        case .tranquila: .systemGreen
        case .atencao: .systemYellow
        case .critica: .systemRed
        }
    }
}

/// O asterisco do Claude, lido do Claude.app instalado (não é copiado para o repositório) e pintado na cor do estado.
/// Sem o Claude.app, usa o asterisco do sistema.
enum MarcaClaude {
    private static let original: NSImage? = {
        let base = "/Applications/Claude.app/Contents/Resources/TrayIconTemplate"
        return NSImage(contentsOfFile: "\(base)@3x.png") ?? NSImage(contentsOfFile: "\(base).png")
    }()

    static func imagem(cor: NSColor, lado: CGFloat) -> NSImage {
        let tamanho = NSSize(width: lado, height: lado)
        guard let original else {
            let simbolo = NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: lado, weight: .bold).applying(.init(paletteColors: [cor]))) ?? NSImage()
            simbolo.isTemplate = false
            return simbolo
        }
        let pintada = NSImage(size: tamanho, flipped: false) { area in
            original.draw(in: area)
            cor.set()
            area.fill(using: .sourceAtop)
            return true
        }
        pintada.isTemplate = false
        pintada.accessibilityDescription = "Limites do Claude"
        return pintada
    }
}

/// Ícone da barra do topo: o asterisco colorido pela pior janela (cinza sem dado).
struct IconeBarra: View {
    let faixa: Faixa?

    var body: some View {
        Image(nsImage: MarcaClaude.imagem(cor: faixa?.corSistema ?? .secondaryLabelColor, lado: 22))
    }
}

/// O que abre ao clicar no ícone.
struct Painel: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cabecalho
                .padding(.bottom, 18)
            if let erro = monitor.erro {
                Label(erro, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
            }
            conteudo
            Divider().padding(.vertical, 14)
            rodape
        }
        .padding(18)
        .frame(width: 320)
    }

    private var cabecalho: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(nsImage: MarcaClaude.imagem(cor: monitor.faixa?.corSistema ?? .secondaryLabelColor, lado: 26))
            VStack(alignment: .leading, spacing: 1) {
                Text("Limites do Claude").font(.system(.headline, design: .rounded))
                Text(monitor.conta).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let data = monitor.atualizadoEm {
                TimelineView(.periodic(from: .now, by: 30)) { contexto in
                    Text(Formato.atualizado(data, agora: contexto.date))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder private var conteudo: some View {
        if monitor.janelas.isEmpty {
            if monitor.erro == nil {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Consultando seus limites…") }
                    .font(.callout).foregroundStyle(.secondary)
            }
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { contexto in
                VStack(spacing: 20) {
                    ForEach(monitor.janelas) { LinhaJanela(janela: $0, agora: contexto.date) }
                }
            }
            .opacity(monitor.erro == nil ? 1 : 0.5)
        }
    }

    private var rodape: some View {
        HStack(spacing: 14) {
            Button {
                Task { await monitor.atualizar() }
            } label: {
                Label("Atualizar", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: monitor.consultando)
            }
            .keyboardShortcut("r")
            .disabled(monitor.consultando)
            Spacer()
            Toggle("Abrir ao iniciar", isOn: $monitor.abrirAoIniciar)
                .toggleStyle(.switch).controlSize(.mini)
            Button("Sair") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

struct LinhaJanela: View {
    let janela: Janela
    let agora: Date

    var body: some View {
        let faixa = Faixa(janela.percentual)
        let passado = janela.tempoPassado(agora: agora)
        // Mais de 10 pontos acima da fração de tempo já corrida = gastando mais rápido que o relógio.
        let acimaDoRitmo = passado.map { janela.percentual > $0 * 100 + 10 } ?? false

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(janela.nome).font(.callout.weight(.medium))
                Spacer()
                Text("\(Int(janela.percentual.rounded()))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(faixa == .tranquila ? AnyShapeStyle(.primary) : AnyShapeStyle(faixa.cor))
                + Text("%").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            BarraUso(fracao: janela.percentual / 100, ritmo: passado, cor: faixa.cor)
            HStack {
                if let reset = janela.resetaEm {
                    Text("reseta \(Formato.falta(reset, agora: agora)) · \(Formato.reset(reset))")
                }
                Spacer()
                if passado != nil {
                    Text(acimaDoRitmo ? "acima do ritmo" : "dentro do ritmo")
                        .foregroundStyle(acimaDoRitmo ? AnyShapeStyle(Faixa.atencao.cor) : AnyShapeStyle(.tertiary))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Barra de uso com o marcador de ritmo: o risco mostra quanto do tempo da janela já passou.
struct BarraUso: View {
    let fracao: Double
    let ritmo: Double?
    let cor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                Capsule().fill(cor.gradient)
                    .frame(width: max(geo.size.width * fracao, fracao > 0 ? 7 : 0))
                if let ritmo {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.primary.opacity(0.55))
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(geo.size.width * ritmo - 1, 0), geo.size.width - 2))
                        .help("Quanto do tempo desta janela já passou")
                }
            }
        }
        .frame(height: 8)
        .animation(.smooth(duration: 0.5), value: fracao)
    }
}
