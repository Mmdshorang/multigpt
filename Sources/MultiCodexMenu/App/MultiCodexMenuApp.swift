import SwiftUI

@main
struct MultiCodexMenuApp: App {
    @NSApplicationDelegateAdaptor(MultiCodexAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AccountsMenuViewModel()

    var body: some Scene {
        MenuBarExtra {
            AccountsMenuContentView(viewModel: viewModel)
                .frame(minWidth: 420, idealWidth: 440)
        } label: {
            MenuBarStatusLabelView(
                title: viewModel.menuBarTitle,
                symbolName: viewModel.menuBarSymbol,
                fiveHourFraction: viewModel.currentFiveHourFraction,
                weeklyFraction: viewModel.currentWeeklyFraction,
                hasError: viewModel.lastRefreshError != nil || viewModel.refreshWarningMessage != nil
            )
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsContentView(viewModel: viewModel)
                .frame(minWidth: 600, idealWidth: 620, minHeight: 420, idealHeight: 440)
        }
    }
}
