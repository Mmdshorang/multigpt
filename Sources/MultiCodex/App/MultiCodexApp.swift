import SwiftUI

@main
struct MultiCodexApp: App {
    @NSApplicationDelegateAdaptor(MultiCodexAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AccountsMenuViewModel()

    var body: some Scene {
        MenuBarExtra {
            AccountsMenuContentView(viewModel: viewModel)
                .frame(
                    minWidth: 380,
                    idealWidth: 400
                )
        } label: {
            let current = viewModel.accounts.first(where: { $0.isCurrent })
            let fiveHourUsed = current?.usage.fiveHour.usedPercent
            let weeklyUsed = current?.usage.weekly.usedPercent
            let isStale = current?.connectionState != .connected

            Image(nsImage: MenuBarIconRenderer.render(
                fiveHourPercent: fiveHourUsed,
                weeklyPercent: weeklyUsed,
                isStale: isStale
            ))
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsContentView(viewModel: viewModel)
                .frame(
                    minWidth: 560,
                    idealWidth: 600,
                    minHeight: 400,
                    idealHeight: 440
                )
        }

        WindowGroup("Batch Login Tracker", id: "batch-login") {
            SequentialLoginTrackerView(viewModel: viewModel)
                .frame(
                    minWidth: 520,
                    idealWidth: 580,
                    minHeight: 400,
                    idealHeight: 480
                )
        }
    }
}
