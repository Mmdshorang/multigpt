using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace MultiCodex.Windows;

public sealed class AccountService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private static readonly Regex ValidName = new("^[A-Za-z0-9_.@-]+$", RegexOptions.Compiled);
    private readonly JsonSerializerOptions jsonOptions = new() { WriteIndented = true };

    public string DataDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MultiCodex");
    private string ConfigPath => Path.Combine(DataDirectory, "config.json");
    private string AccountsDirectory => Path.Combine(DataDirectory, "accounts");
    private string CodexAuthPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "auth.json");

    public AccountService()
    {
        Directory.CreateDirectory(AccountsDirectory);
    }

    public List<AccountModel> LoadAccounts()
    {
        var config = LoadConfig();
        return config.Accounts.Keys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(x => x == config.CurrentAccount)
            .Select(name => new AccountModel
            {
                Name = name,
                IsCurrent = name == config.CurrentAccount,
                HasAuth = File.Exists(AccountAuthPath(name))
            }).ToList();
    }

    public void ImportCurrentAuth(string name)
    {
        ValidateName(name);
        if (!File.Exists(CodexAuthPath))
            throw new InvalidOperationException("No Codex login found. Run Codex login first.");

        var config = LoadConfig();
        if (config.Accounts.ContainsKey(name))
            throw new InvalidOperationException("An account with this name already exists.");

        var directory = Path.Combine(AccountsDirectory, name);
        Directory.CreateDirectory(directory);
        File.Copy(CodexAuthPath, AccountAuthPath(name), true);
        config.Accounts[name] = new Dictionary<string, object>();
        config.CurrentAccount = name;
        SaveConfig(config);
    }

    public void SwitchAccount(string name)
    {
        var config = LoadConfig();
        if (!config.Accounts.ContainsKey(name)) throw new InvalidOperationException("Unknown account.");
        var target = AccountAuthPath(name);
        if (!File.Exists(target)) throw new InvalidOperationException("This account has no saved login.");

        Directory.CreateDirectory(Path.GetDirectoryName(CodexAuthPath)!);
        var staged = CodexAuthPath + ".multicodex-" + Guid.NewGuid().ToString("N");
        File.Copy(target, staged, true);
        File.Move(staged, CodexAuthPath, true);
        config.CurrentAccount = name;
        SaveConfig(config);
    }

    public void RemoveAccount(string name)
    {
        var config = LoadConfig();
        config.Accounts.Remove(name);
        var directory = Path.Combine(AccountsDirectory, name);
        if (Directory.Exists(directory)) Directory.Delete(directory, true);
        if (config.CurrentAccount == name)
        {
            config.CurrentAccount = config.Accounts.Keys.OrderBy(x => x).FirstOrDefault();
            if (config.CurrentAccount is { } next) SwitchAccountAndSave(next, config);
            else SaveConfig(config);
        }
        else SaveConfig(config);
    }

    public async Task<(string FiveHour, string Weekly)> FetchUsageAsync(string name)
    {
        var auth = JsonNode.Parse(await File.ReadAllTextAsync(AccountAuthPath(name)))?.AsObject()
                   ?? throw new InvalidOperationException("Invalid auth file.");
        if (auth["OPENAI_API_KEY"] is not null) return ("N/A", "N/A");
        var tokens = auth["tokens"]?.AsObject() ?? throw new InvalidOperationException("Login required");
        var accessToken = tokens["access_token"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(accessToken)) throw new InvalidOperationException("Login required");

        using var request = new HttpRequestMessage(HttpMethod.Get, "https://chatgpt.com/backend-api/wham/usage");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.UserAgent.ParseAdd("multicodex-windows");
        var accountId = tokens["account_id"]?.GetValue<string>();
        if (!string.IsNullOrWhiteSpace(accountId)) request.Headers.TryAddWithoutValidation("ChatGPT-Account-Id", accountId);

        using var response = await Http.SendAsync(request);
        if (response.StatusCode is System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden)
            throw new InvalidOperationException("Session expired; log in again");
        response.EnsureSuccessStatusCode();
        var body = JsonNode.Parse(await response.Content.ReadAsStringAsync())?.AsObject();
        var rateLimit = body?["rate_limit"]?.AsObject();
        return (Percent(rateLimit?["primary_window"]), Percent(rateLimit?["secondary_window"]));
    }

    public async Task<string> GetRuntimeLabelAsync()
    {
        try
        {
            var startInfo = new ProcessStartInfo("codex", "--version")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using var process = Process.Start(startInfo)!;
            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            return process.ExitCode == 0 ? output.Trim() : "Codex unavailable";
        }
        catch { return "Codex unavailable"; }
    }

    public void LaunchLogin()
    {
        Process.Start(new ProcessStartInfo("cmd.exe", "/k codex login") { UseShellExecute = true });
    }

    private void SwitchAccountAndSave(string name, ConfigFile config)
    {
        var target = AccountAuthPath(name);
        if (File.Exists(target))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(CodexAuthPath)!);
            File.Copy(target, CodexAuthPath, true);
        }
        SaveConfig(config);
    }

    private ConfigFile LoadConfig()
    {
        if (!File.Exists(ConfigPath)) return new ConfigFile();
        try
        {
            var config = JsonSerializer.Deserialize<ConfigFile>(File.ReadAllText(ConfigPath));
            return config?.Version == 2 ? config : RecoverConfig();
        }
        catch { return RecoverConfig(); }
    }

    private ConfigFile RecoverConfig()
    {
        var config = new ConfigFile();
        if (Directory.Exists(AccountsDirectory))
            foreach (var directory in Directory.EnumerateDirectories(AccountsDirectory))
                config.Accounts[Path.GetFileName(directory)] = new Dictionary<string, object>();
        return config;
    }

    private void SaveConfig(ConfigFile config)
    {
        Directory.CreateDirectory(DataDirectory);
        var temporary = ConfigPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(config, jsonOptions));
        File.Move(temporary, ConfigPath, true);
    }

    private string AccountAuthPath(string name) => Path.Combine(AccountsDirectory, name, "auth.json");

    private static string Percent(JsonNode? window)
    {
        var value = window?["used_percent"]?.GetValue<double?>();
        return value is null ? "--" : $"{value:0.#}%";
    }

    private static void ValidateName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || !ValidName.IsMatch(name))
            throw new InvalidOperationException("Use letters, numbers, underscore, dash, dot, or @.");
    }

    private sealed class ConfigFile
    {
        public int Version { get; set; } = 2;
        public string? CurrentAccount { get; set; }
        public Dictionary<string, Dictionary<string, object>> Accounts { get; set; } = new();
    }
}
