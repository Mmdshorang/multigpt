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
    private static readonly HashSet<string> ReservedDeviceNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    private readonly JsonSerializerOptions jsonOptions = new() { WriteIndented = true };
    private readonly string codexExecutable;
    private readonly string userProfileDirectory;

    public string DataDirectory { get; }
    private string ConfigPath => Path.Combine(DataDirectory, "config.json");
    private string AccountsDirectory => Path.Combine(DataDirectory, "accounts");
    private string ManagedHomesDirectory => Path.Combine(DataDirectory, "managed-homes");
    private string CodexAuthPath => Path.Combine(userProfileDirectory, ".codex", "auth.json");

    public AccountService(
        string? dataDirectory = null,
        string? userProfileDirectory = null,
        string codexExecutable = "codex")
    {
        DataDirectory = dataDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MultiCodex");
        this.userProfileDirectory = userProfileDirectory ??
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        this.codexExecutable = string.IsNullOrWhiteSpace(codexExecutable) ? "codex" : codexExecutable;

        Directory.CreateDirectory(AccountsDirectory);
        Directory.CreateDirectory(ManagedHomesDirectory);
    }

    public List<AccountModel> LoadAccounts()
    {
        var config = LoadConfig();
        foreach (var name in config.Accounts.Keys) MigrateLegacyAuthIfNeeded(name);

        return config.Accounts.Keys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
            .OrderByDescending(x => string.Equals(x, config.CurrentAccount, StringComparison.OrdinalIgnoreCase))
            .Select(name => new AccountModel
            {
                Name = name,
                IsCurrent = string.Equals(name, config.CurrentAccount, StringComparison.OrdinalIgnoreCase),
                HasAuth = File.Exists(AccountAuthPath(name))
            }).ToList();
    }

    public void ImportCurrentAuth(string name)
    {
        name = ValidateName(name);
        if (!File.Exists(CodexAuthPath))
            throw new InvalidOperationException("No Codex login found. Run Codex login first.");

        var config = LoadConfig();
        if (config.Accounts.ContainsKey(name))
            throw new InvalidOperationException("An account with this name already exists.");

        var directory = Path.Combine(AccountsDirectory, name);
        Directory.CreateDirectory(directory);
        Directory.CreateDirectory(AccountHomePath(name));
        File.Copy(CodexAuthPath, AccountAuthPath(name), true);
        config.Accounts[name] = new Dictionary<string, object>();
        config.CurrentAccount = name;
        SaveConfig(config);
    }

    public void SwitchAccount(string name)
    {
        name = ValidateName(name);
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
        name = ValidateName(name);
        var config = LoadConfig();
        config.Accounts.Remove(name);
        var directory = Path.Combine(AccountsDirectory, name);
        if (Directory.Exists(directory)) Directory.Delete(directory, true);
        var home = AccountHomePath(name);
        if (Directory.Exists(home)) Directory.Delete(home, true);
        if (string.Equals(config.CurrentAccount, name, StringComparison.OrdinalIgnoreCase))
        {
            config.CurrentAccount = config.Accounts.Keys
                .Where(accountName => File.Exists(AccountAuthPath(accountName)))
                .OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault();
            if (config.CurrentAccount is { } next) SwitchAccountAndSave(next, config);
            else SaveConfig(config);
        }
        else SaveConfig(config);
    }

    public async Task<(string FiveHour, string Weekly)> FetchUsageAsync(string name)
    {
        name = ValidateName(name);
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
            var startInfo = new ProcessStartInfo(codexExecutable, "--version")
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

    public LoginLaunch CreateLogin(string name)
    {
        name = ValidateName(name);
        var config = LoadConfig();
        if (!config.Accounts.ContainsKey(name))
        {
            config.Accounts[name] = new Dictionary<string, object>();
            if (string.IsNullOrWhiteSpace(config.CurrentAccount)) config.CurrentAccount = name;
            SaveConfig(config);
        }

        var accountHome = AccountHomePath(name);
        Directory.CreateDirectory(accountHome);
        Directory.CreateDirectory(DataDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(CodexAuthPath)!);

        var startInfo = new ProcessStartInfo(codexExecutable)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("login");
        startInfo.ArgumentList.Add("-c");
        startInfo.ArgumentList.Add("cli_auth_credentials_store=\"file\"");
        startInfo.ArgumentList.Add("--device-auth");
        startInfo.Environment["CODEX_HOME"] = accountHome;
        startInfo.Environment["MULTICODEX_HOME"] = DataDirectory;

        return new LoginLaunch(name, startInfo);
    }

    public void CompleteLogin(string name)
    {
        name = ValidateName(name);
        var authPath = AccountAuthPath(name);
        if (!File.Exists(authPath))
            throw new InvalidOperationException(
                "Codex finished without saving a login. Device-code login may be disabled in ChatGPT Settings > Security or by your workspace administrator.");

        var config = LoadConfig();
        if (!string.Equals(config.CurrentAccount, name, StringComparison.OrdinalIgnoreCase)) return;

        Directory.CreateDirectory(Path.GetDirectoryName(CodexAuthPath)!);
        var staged = CodexAuthPath + ".multicodex-" + Guid.NewGuid().ToString("N");
        File.Copy(authPath, staged, true);
        File.Move(staged, CodexAuthPath, true);
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
            return config?.Version == 2 ? NormalizeConfig(config) : RecoverConfig();
        }
        catch { return RecoverConfig(); }
    }

    private static ConfigFile NormalizeConfig(ConfigFile config)
    {
        var normalized = new ConfigFile();
        if (config.Accounts is null) return normalized;

        foreach (var entry in config.Accounts)
        {
            if (!TryValidateName(entry.Key, out var name)) continue;
            normalized.Accounts.TryAdd(name, entry.Value);
            if (string.Equals(config.CurrentAccount, entry.Key, StringComparison.OrdinalIgnoreCase))
                normalized.CurrentAccount = name;
        }

        if (normalized.CurrentAccount is not null && !normalized.Accounts.ContainsKey(normalized.CurrentAccount))
            normalized.CurrentAccount = null;

        return normalized;
    }

    private ConfigFile RecoverConfig()
    {
        var config = new ConfigFile();
        if (Directory.Exists(AccountsDirectory))
            foreach (var directory in Directory.EnumerateDirectories(AccountsDirectory))
                if (TryValidateName(Path.GetFileName(directory), out var name))
                    config.Accounts[name] = new Dictionary<string, object>();
        if (Directory.Exists(ManagedHomesDirectory))
            foreach (var directory in Directory.EnumerateDirectories(ManagedHomesDirectory))
                if (TryValidateName(Path.GetFileName(directory), out var name))
                    config.Accounts.TryAdd(name, new Dictionary<string, object>());
        return config;
    }

    private void SaveConfig(ConfigFile config)
    {
        Directory.CreateDirectory(DataDirectory);
        var temporary = ConfigPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(config, jsonOptions));
        File.Move(temporary, ConfigPath, true);
    }

    private string AccountHomePath(string name) => Path.Combine(ManagedHomesDirectory, name);

    private string AccountAuthPath(string name) => Path.Combine(AccountHomePath(name), "auth.json");

    private string LegacyAccountAuthPath(string name) => Path.Combine(AccountsDirectory, name, "auth.json");

    private void MigrateLegacyAuthIfNeeded(string name)
    {
        var legacy = LegacyAccountAuthPath(name);
        var current = AccountAuthPath(name);
        if (!File.Exists(legacy) || File.Exists(current)) return;

        Directory.CreateDirectory(AccountHomePath(name));
        File.Copy(legacy, current, false);
    }

    private static string Percent(JsonNode? window)
    {
        var value = window?["used_percent"]?.GetValue<double?>();
        return value is null ? "--" : $"{value:0.#}%";
    }

    private static string ValidateName(string name)
    {
        if (!TryValidateName(name, out var normalized))
            throw new InvalidOperationException("Use letters, numbers, underscore, dash, dot, or @.");
        return normalized;
    }

    private static bool TryValidateName(string? name, out string normalized)
    {
        normalized = name?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(normalized) || !ValidName.IsMatch(normalized))
            return false;

        if (normalized is "." or ".." || normalized.EndsWith('.'))
            return false;

        var deviceName = normalized.Split('.')[0];
        return !ReservedDeviceNames.Contains(deviceName);
    }

    private sealed class ConfigFile
    {
        public int Version { get; set; } = 2;
        public string? CurrentAccount { get; set; }
        public Dictionary<string, Dictionary<string, object>> Accounts { get; set; } =
            new(StringComparer.OrdinalIgnoreCase);
    }

    public sealed record LoginLaunch(string AccountName, ProcessStartInfo StartInfo);
}
