using System.Diagnostics;
using System.IO;
using System.Text;
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
    private readonly StringBuilder outputLog = new();
    private CancellationTokenSource? cancellation;
    private Process? loginProcess;
    private CodexLoginMethod? activeMethod;
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
        Closing += LoginWindow_Closing;
    }

    private async Task RunLoginAsync(CodexLoginMethod method)
    {
        if (isRunning) return;
        PrepareLoginAttempt(method);
        isRunning = true;

        try
        {
            var launch = service.CreateLogin(accountName, method);
            loginProcess = new Process { StartInfo = launch.StartInfo };
            if (!loginProcess.Start()) throw new InvalidOperationException("Could not start Codex CLI.");

            var methodName = method == CodexLoginMethod.DeviceCode ? "device-code" : "normal browser";
            AppendOutput($"Starting {methodName} login for {accountName}...{Environment.NewLine}");
            var token = cancellation!.Token;
            var standardOutput = PumpOutputAsync(loginProcess.StandardOutput, token);
            var standardError = PumpOutputAsync(loginProcess.StandardError, token);
            await loginProcess.WaitForExitAsync(token);
            await Task.WhenAll(standardOutput, standardError);

            if (loginProcess.ExitCode != 0)
                throw new InvalidOperationException(LoginFailureMessage(method, loginProcess.ExitCode));

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
            cancellation?.Dispose();
            cancellation = null;
            if (!LoginSucceeded)
            {
                MethodPanel.IsEnabled = true;
                CancelButton.IsEnabled = true;
            }
        }
    }

    private void PrepareLoginAttempt(CodexLoginMethod method)
    {
        activeMethod = method;
        cancellation?.Dispose();
        cancellation = new CancellationTokenSource();
        signInUrl = null;
        deviceCode = null;
        browserOpened = false;
        outputLog.Clear();
        OutputBox.Clear();
        CodeText.Text = "waiting...";
        CopyCodeButton.IsEnabled = false;
        OpenPageButton.IsEnabled = false;
        DeviceCodePanel.Visibility = Visibility.Visible;
        CodeDisplayBorder.Visibility = method == CodexLoginMethod.DeviceCode
            ? Visibility.Visible
            : Visibility.Collapsed;
        CopyCodeButton.Visibility = method == CodexLoginMethod.DeviceCode
            ? Visibility.Visible
            : Visibility.Collapsed;
        MethodPanel.IsEnabled = false;
        CancelButton.IsEnabled = true;
        CloseButton.IsEnabled = false;
        StatusText.Foreground = (System.Windows.Media.Brush)FindResource("MutedBrush");
        StatusText.Text = method == CodexLoginMethod.DeviceCode
            ? "Requesting a one-time code..."
            : "Checking callback port 1455 and starting browser login...";
        MethodHelpText.Text = method == CodexLoginMethod.DeviceCode
            ? "Enter the one-time code on the ChatGPT page in your browser, not in a terminal."
            : "Codex will open the browser and receive the result on localhost:1455. Keep this window open until login finishes.";
    }

    private async Task PumpOutputAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
            await Dispatcher.InvokeAsync(() => AppendOutput(line + Environment.NewLine));
    }

    private void AppendOutput(string text)
    {
        var clean = AnsiPattern.Replace(text, "").Replace("\r", "");
        outputLog.Append(clean);
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
            if (activeMethod == CodexLoginMethod.DeviceCode && !browserOpened) OpenSignInPage();
        }
    }

    private string LoginFailureMessage(CodexLoginMethod method, int exitCode)
    {
        var output = outputLog.ToString();
        if (method == CodexLoginMethod.BrowserCallback &&
            (output.Contains("10013", StringComparison.OrdinalIgnoreCase) ||
             output.Contains("address already in use", StringComparison.OrdinalIgnoreCase) ||
             output.Contains("access permissions", StringComparison.OrdinalIgnoreCase)))
        {
            return "Windows blocked local callback port 1455. Close other Codex login windows and retry, or choose Device Code above.";
        }

        if (method == CodexLoginMethod.DeviceCode &&
            output.Contains("device code login is not enabled", StringComparison.OrdinalIgnoreCase))
        {
            return "Device Code is disabled for this account or workspace. Enable it in ChatGPT Settings > Security, or choose Normal browser login above.";
        }

        return $"Codex login stopped with exit code {exitCode}. Check the output above, then retry with either sign-in method.";
    }

    private void OpenSignInPage()
    {
        if (string.IsNullOrWhiteSpace(signInUrl)) return;
        try
        {
            Process.Start(new ProcessStartInfo(signInUrl) { UseShellExecute = true });
            browserOpened = true;
            StatusText.Text = activeMethod == CodexLoginMethod.DeviceCode
                ? "Complete sign-in in the browser. Enter the code there, not here."
                : "Complete sign-in in the browser and return here.";
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

    private async void DeviceCode_Click(object sender, RoutedEventArgs e) =>
        await RunLoginAsync(CodexLoginMethod.DeviceCode);

    private async void BrowserCallback_Click(object sender, RoutedEventArgs e) =>
        await RunLoginAsync(CodexLoginMethod.BrowserCallback);

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (isRunning)
        {
            CancelLogin();
            StatusText.Text = "Cancelling login...";
        }
        else
        {
            Close();
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void LoginWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e) => CancelLogin();

    private void CancelLogin()
    {
        if (!isRunning) return;
        cancellation?.Cancel();
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
