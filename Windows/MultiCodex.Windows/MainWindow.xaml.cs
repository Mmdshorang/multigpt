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
    }

    public async Task RefreshAccountsAsync()
    {
        try
        {
            RuntimeText.Text = await service.GetRuntimeLabelAsync();
            var accounts = service.LoadAccounts();
            Accounts.Clear();
            foreach (var account in accounts) Accounts.Add(account);
            FooterText.Text = accounts.Count == 0
                ? "No saved accounts. Log in with Codex, then click Add current login."
                : $"{accounts.Count} account(s). Usage refreshed at {DateTime.Now:t}.";

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

    private void Login_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            service.LaunchLogin();
            FooterText.Text = "Finish login in the terminal, then click Add current login.";
        }
        catch (Exception ex) { ShowError(ex); }
    }

    private async void Add_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new InputDialog { Owner = this };
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

    private static void ShowError(Exception ex) =>
        MessageBox.Show(ex.Message, "MultiCodex", MessageBoxButton.OK, MessageBoxImage.Error);
}
