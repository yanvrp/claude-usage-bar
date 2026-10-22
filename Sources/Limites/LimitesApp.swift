import SwiftUI

/// App só de barra do topo (sem ícone no Dock: LSUIElement no Info.plist).
@main
struct LimitesApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            Painel(monitor: monitor)
        } label: {
            IconeBarra(faixa: monitor.faixa)
        }
        .menuBarExtraStyle(.window)
    }
}
