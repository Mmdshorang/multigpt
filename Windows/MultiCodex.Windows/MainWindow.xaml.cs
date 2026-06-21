using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Windows;
using MessageBox = System.Windows.MessageBox;

namespace MultiCodex.Windows;

public partial class MainWindow : Window
{
    private readonly AccountService service = new();
    public ObservableCollection<AccountModel> Accounts { get; } = [];
    public bool IsExiting { get; set; }

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;
        Loaded += async (_, _) => await RefreshAccountsAsync();
        UpdateSelectionButtons();
    }

    public async Task RefreshAccountsAsync()
    {
        try
        {
            var selectedName = (AccountsGrid.SelectedItem as AccountModel)?.Name;
            RuntimeText.Text = await service.GetRuntimeLabelAsync();
            var accounts = service.LoadAccounts();
            Accounts.Clear();
            foreach (var account in accounts) Accounts.Add(account);
            if (!string.IsNullOrWhiteSpace(selectedName))
                AccountsGrid.SelectedItem = Accounts.FirstOrDefault(x =>
                    string.Equals(x.Name, selectedName, StringComparison.OrdinalIgnoreCase));
            FooterText.Text = accounts.Count == 0
                ? "No saved accounts. Click Log in account, then choose a sign-in method."
                : $"{accounts.Count} account(s). Usage refreshed at {DateTime.Now:t}.";
            UpdateSelectionButtons();

            await Task.WhenAll(Accounts.Where(x => x.HasAuth).Select(RefreshUsageAsync));
        }
        catch (Exception ex)
        {
            ShowError(ex);
        }
    }

    private async Task RefreshUsageAsync(AccountModel account)
    {
        account.Status = "Loading usage...";
        try
        {
            var usage = await service.FetchUsageAsync(account.Name);
            account.FiveHour = usage.FiveHour;
            account.Weekly = usage.Weekly;
            account.Status = "Ready";
        }
        catch (Exception ex)
        {
            account.Status = ex.Message;
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await RefreshAccountsAsync();

    private async void Login_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new InputDialog("Account name", "Choose a name for this Codex login", "Start login")
        {
            Owner = this
        };
        if (dialog.ShowDialog() != true) return;

        try
        {
            var loginWindow = new LoginWindow(service, dialog.Value) { Owner = this };
            loginWindow.ShowDialog();
            FooterText.Text = loginWindow.LoginSucceeded
                ? $"Login saved for {dialog.Value}. Usage is being refreshed."
                : $"Login for {dialog.Value} was not completed.";
            await RefreshAccountsAsync();
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new InputDialog("Import current login", "Name for the currently active Codex login", "Import account")
        {
            Owner = this
        };
        if (dialog.ShowDialog() != true) return;
        try
        {
            service.ImportCurrentAuth(dialog.Value);
            await RefreshAccountsAsync();
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private async void Switch_Click(object sender, RoutedEventArgs e)
    {
        if (AccountsGrid.SelectedItem is not AccountModel account) return;
        try
        {
            service.SwitchAccount(account.Name);
            FooterText.Text = $"Switched Codex to {account.Name}. New terminals will use this account.";
            await RefreshAccountsAsync();
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (AccountsGrid.SelectedItem is not AccountModel account) return;
        if (MessageBox.Show($"Remove '{account.Name}' from MultiCodex?", "Confirm", MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try
        {
            service.RemoveAccount(account.Name);
            await RefreshAccountsAsync();
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e) =>
        Process.Start(new ProcessStartInfo("explorer.exe", service.DataDirectory) { UseShellExecute = true });

    private void AccountsGrid_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e) =>
        UpdateSelectionButtons();

    private void UpdateSelectionButtons()
    {
        if (!IsLoaded && SwitchButton is null) return;
        var selected = AccountsGrid.SelectedItem as AccountModel;
        SwitchButton.IsEnabled = selected is { HasAuth: true, IsCurrent: false };
        RemoveButton.IsEnabled = selected is not null;
    }

    private static void ShowError(Exception ex) =>
        MessageBox.Show(ex.Message, "MultiCodex", MessageBoxButton.OK, MessageBoxImage.Error);
}
