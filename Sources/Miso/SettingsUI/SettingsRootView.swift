import MisoCore
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel
    @State private var pane: SettingsPane? = .status
    @State private var scope: SettingsScope = .global

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            detail
                .navigationTitle(pane?.title ?? "Miso")
                .toolbar {
                    if pane?.usesScope == true {
                        ToolbarItemGroup {
                            ScopeMenu(model: model, scope: $scope)
                            ResetProfileButton(model: model, scope: scope)
                        }
                    }
                }
        }
        .frame(minWidth: 680, minHeight: 500)
    }

    @ViewBuilder private var detail: some View {
        switch pane ?? .status {
        case .status: StatusPane(model: model)
        case .pointer: PointerPane(model: model, scope: scope)
        case .scrolling: ScrollingPane(model: model, scope: scope)
        case .buttons: ButtonsPane(model: model, scope: scope)
        }
    }
}
