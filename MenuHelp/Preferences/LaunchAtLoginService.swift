import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginService: ObservableObject {
    static let shared = LaunchAtLoginService()

    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    private init() {
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            errorMessage = String(localized: "Não foi possível alterar a inicialização automática.")
        }
    }

    func refreshStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            errorMessage = nil
        case .requiresApproval:
            isEnabled = true
            errorMessage = String(localized: "Autorize o MenuHelp em Ajustes do Sistema → Geral → Itens de Início.")
        case .notRegistered:
            isEnabled = false
            errorMessage = nil
        case .notFound:
            isEnabled = false
            errorMessage = String(localized: "O MenuHelp precisa estar na pasta Aplicativos.")
        @unknown default:
            isEnabled = false
            errorMessage = String(localized: "Não foi possível verificar a inicialização automática.")
        }
    }
}
