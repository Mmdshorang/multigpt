using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;

namespace MultiCodex.Windows;

public partial class LoginWindow : Window
{
    private static readonly Regex AnsiPattern = new(@"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])", RegexOptions.Compiled);
    private static readonly Regex UrlPattern = new(@"https?://[^\s<>\""']+", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    private static readonly Regex DeviceCodePattern = new(
        @"(?<![A-Z0-9])[A-Z0-9]{4}(?:-[A-Z0-9]{4})+(?![A-Z0-9])",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private readonly AccountService service;
    private readonly string accountName;
    private readonly CancellationTokenSource cancellation = new();
    private Process? loginProcess;
    private string? signInUrl;
    private string? deviceCode;
    private bool isRunning;
    private bool browserOpened;

    public bool LoginSucceeded { get; private set; }

    public LoginWindow(AccountService service, string accountName)
    {
        InitializeComponent();
        this.service = service;
        this.accountName = accountName;
        TitleText.Text = $"Sign in: {accountName}";
        Loaded += async (_, _) => await RunLoginAsync();
        Closing += LoginWindow_Closing;
    }

    private async Task RunLoginAsync()
    {
        if (isRunning) return;
        isRunning = true;

        try
        {
            var launch = service.CreateLogin(accountName);
            loginProcess = new Process { StartInfo = launch.StartInfo };
            if (!loginProcess.Start()) throw new InvalidOperationException("Could not start Codex CLI.");

            AppendOutput($"Starting device-code login for {accountName}...{Environment.NewLine}");
            var standardOutput = PumpOutputAsync(loginProcess.StandardOutput, cancellation.Token);
            var standardError = PumpOutputAsync(loginProcess.StandardError, cancellation.Token);
            await loginProcess.WaitForExitAsync(cancellation.Token);
            await Task.WhenAll(standardOutput, standardError);

            if (loginProcess.ExitCode != 0)
                throw new InvalidOperationException(
                    $"Codex login stopped with exit code {loginProcess.ExitCode}. Check the output above. If device-code login is blocked, enable it in ChatGPT Settings > Security or ask your workspace administrator.");

            service.CompleteLogin(accountName);
            LoginSucceeded = true;
            StatusText.Text = $"Login saved for {accountName}.";
            AppendOutput($"{Environment.NewLine}Login saved successfully.{Environment.NewLine}");
        }
        catch (OperationCanceledException)
        {
            StatusText.Text = "Login cancelled.";
        }
        catch (Exception ex)
        {
            StatusText.Text = ex.Message;
            StatusText.Foreground = System.Windows.Media.Brushes.OrangeRed;
            AppendOutput($"{Environment.NewLine}Error: {ex.Message}{Environment.NewLine}");
        }
        finally
        {
            isRunning = false;
            CancelButton.IsEnabled = false;
            CloseButton.IsEnabled = true;
            loginProcess?.Dispose();
            loginProcess = null;
        }
    }

    private async Task PumpOutputAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
            await Dispatcher.InvokeAsync(() => AppendOutput(line + Environment.NewLine));
    }

    private void AppendOutput(string text)
    {
        var clean = AnsiPattern.Replace(text, "").Replace("\r", "");
        OutputBox.AppendText(clean);
        OutputBox.ScrollToEnd();

        if (deviceCode is null && DeviceCodePattern.Match(clean) is { Success: true } codeMatch)
        {
            deviceCode = codeMatch.Value.ToUpperInvariant();
            CodeText.Text = deviceCode;
            CopyCodeButton.IsEnabled = true;
        }

        if (signInUrl is null && UrlPattern.Match(clean) is { Success: true } urlMatch)
        {
            signInUrl = urlMatch.Value.TrimEnd('.', ',', ')', ']', '`');
            OpenPageButton.IsEnabled = true;
            if (!browserOpened) OpenSignInPage();
        }
    }

    private void OpenSignInPage()
    {
        if (string.IsNullOrWhiteSpace(signInUrl)) return;
        try
        {
            Process.Start(new ProcessStartInfo(signInUrl) { UseShellExecute = true });
            browserOpened = true;
            StatusText.Text = "Complete sign-in in the browser. Enter the code there, not here.";
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Could not open the browser: {ex.Message}. Use the link in the output.";
        }
    }

    private void CopyCode_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(deviceCode)) System.Windows.Clipboard.SetText(deviceCode);
    }

    private void OpenPage_Click(object sender, RoutedEventArgs e) => OpenSignInPage();

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        CancelLogin();
        StatusText.Text = "Cancelling login...";
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void LoginWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e) => CancelLogin();

    private void CancelLogin()
    {
        if (!isRunning) return;
        cancellation.Cancel();
        try
        {
            if (loginProcess is { HasExited: false }) loginProcess.Kill(true);
        }
        catch
        {
            // The process may have exited between the state check and Kill.
        }
    }
}
