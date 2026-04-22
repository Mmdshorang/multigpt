import SwiftUI

@main
struct MultiCodexApp: App {
    @NSApplicationDelegateAdaptor(MultiCodexAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AccountsMenuViewModel()

    var body: some Scene {
        MenuBarExtra {
            AccountsMenuContentView(viewModel: viewModel)
                .frame(
                    minWidth: DashboardTokens.scaled(420),
                    idealWidth: DashboardTokens.scaled(440)
                )
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
                .frame(
                    minWidth: DashboardTokens.scaled(600),
                    idealWidth: DashboardTokens.scaled(620),
                    minHeight: DashboardTokens.scaled(420),
                    idealHeight: DashboardTokens.scaled(440)
                )
        }

        WindowGroup("Batch Login Tracker", id: "batch-login") {
            SequentialLoginTrackerView(viewModel: viewModel)
                .frame(
                    minWidth: DashboardTokens.scaled(560),
                    idealWidth: DashboardTokens.scaled(620),
                    minHeight: DashboardTokens.scaled(420),
                    idealHeight: DashboardTokens.scaled(520)
                )
        }
    }
}
