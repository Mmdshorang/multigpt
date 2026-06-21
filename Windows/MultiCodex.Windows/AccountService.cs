using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace MultiCodex.Windows;

public enum CodexLoginMethod
{
    DeviceCode,
    BrowserCallback
}

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
            var startInfo = CreateCodexStartInfo(["--version"]);
            using var process = Process.Start(startInfo)!;
            var output = await process.StandardOutput.ReadToEndAsync();
            var error = await process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            var label = string.IsNullOrWhiteSpace(output) ? error : output;
            return process.ExitCode == 0 ? label.Trim() : "Codex unavailable";
        }
        catch { return "Codex unavailable"; }
    }

    public LoginLaunch CreateLogin(string name, CodexLoginMethod method)
    {
        name = ValidateName(name);
        if (method == CodexLoginMethod.BrowserCallback) EnsureBrowserCallbackAvailable();

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

        var arguments = new List<string>
        {
            "login",
            "-c",
            "cli_auth_credentials_store=file"
        };
        if (method == CodexLoginMethod.DeviceCode) arguments.Add("--device-auth");

        var startInfo = CreateCodexStartInfo(arguments);
        startInfo.Environment["CODEX_HOME"] = accountHome;
        startInfo.Environment["MULTICODEX_HOME"] = DataDirectory;

        return new LoginLaunch(name, method, startInfo);
    }

    public void CompleteLogin(string name)
    {
        name = ValidateName(name);
        var authPath = AccountAuthPath(name);
        if (!File.Exists(authPath))
            throw new InvalidOperationException(
                "Codex finished without saving a login. Retry the login and check the Codex output for the specific authentication error.");

        var config = LoadConfig();
        if (!string.Equals(config.CurrentAccount, name, StringComparison.OrdinalIgnoreCase)) return;

        Directory.CreateDirectory(Path.GetDirectoryName(CodexAuthPath)!);
        var staged = CodexAuthPath + ".multicodex-" + Guid.NewGuid().ToString("N");
        File.Copy(authPath, staged, true);
        File.Move(staged, CodexAuthPath, true);
    }

    public static void EnsureBrowserCallbackAvailable()
    {
        TcpListener? listener = null;
        try
        {
            listener = new TcpListener(IPAddress.Loopback, 1455);
            listener.Start();
        }
        catch (SocketException ex)
        {
            var reason = ex.SocketErrorCode == SocketError.AddressAlreadyInUse
                ? "another application is already using it"
                : "Windows or a security policy blocked it";
            throw new InvalidOperationException(
                $"Normal browser login needs local callback port 1455, but {reason} ({ex.SocketErrorCode}, OS error {ex.ErrorCode}). Close other Codex login windows and retry, or use Device Code.",
                ex);
        }
        finally
        {
            listener?.Stop();
        }
    }

    private ProcessStartInfo CreateCodexStartInfo(IReadOnlyList<string> arguments)
    {
        var executable = ResolveCodexExecutable();
        var extension = Path.GetExtension(executable);
        ProcessStartInfo startInfo;

        if (extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".bat", StringComparison.OrdinalIgnoreCase))
        {
            var commandInterpreter = Environment.GetEnvironmentVariable("ComSpec");
            if (string.IsNullOrWhiteSpace(commandInterpreter) || !File.Exists(commandInterpreter))
                commandInterpreter = Path.Combine(Environment.SystemDirectory, "cmd.exe");

            var command = string.Join(" ", new[] { QuoteCommandArgument(executable) }
                .Concat(arguments.Select(QuoteCommandArgument)));
            startInfo = new ProcessStartInfo(commandInterpreter)
            {
                // cmd.exe requires the command to be wrapped in an additional pair of quotes
                // when the executable path itself is quoted.
                Arguments = $"/d /s /c \"{command}\""
            };
        }
        else
        {
            startInfo = new ProcessStartInfo(executable);
            foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
        }

        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        return startInfo;
    }

    private string ResolveCodexExecutable()
    {
        var configured = Environment.ExpandEnvironmentVariables(codexExecutable.Trim().Trim('"'));
        if (string.IsNullOrWhiteSpace(configured)) configured = "codex";

        if (Path.IsPathFullyQualified(configured) ||
            configured.Contains(Path.DirectorySeparatorChar) ||
            configured.Contains(Path.AltDirectorySeparatorChar))
        {
            if (TryResolveCommandPath(configured, out var explicitPath)) return explicitPath;
            throw CodexNotFound(configured);
        }

        foreach (var directory in CodexSearchDirectories())
        {
            if (TryResolveCommandPath(Path.Combine(directory, configured), out var resolved))
                return resolved;
        }

        throw CodexNotFound(configured);
    }

    private IEnumerable<string> CodexSearchDirectories()
    {
        var directories = new List<string>();
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        directories.AddRange(path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries));

        var roamingAppData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (!string.IsNullOrWhiteSpace(roamingAppData)) directories.Add(Path.Combine(roamingAppData, "npm"));

        AddEditorCodexDirectories(directories, Path.Combine(userProfileDirectory, ".vscode", "extensions"));
        AddEditorCodexDirectories(directories, Path.Combine(userProfileDirectory, ".cursor", "extensions"));

        return directories
            .Select(directory => Environment.ExpandEnvironmentVariables(directory.Trim().Trim('"')))
            .Where(directory => !string.IsNullOrWhiteSpace(directory) && Directory.Exists(directory))
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static void AddEditorCodexDirectories(List<string> directories, string extensionsDirectory)
    {
        if (!Directory.Exists(extensionsDirectory)) return;

        try
        {
            directories.AddRange(Directory.EnumerateDirectories(extensionsDirectory, "openai.chatgpt-*")
                .OrderByDescending(Directory.GetLastWriteTimeUtc)
                .Select(directory => Path.Combine(directory, "bin", "windows-x86_64")));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static bool TryResolveCommandPath(string basePath, out string resolved)
    {
        resolved = "";
        var extension = Path.GetExtension(basePath);
        if (!string.IsNullOrWhiteSpace(extension))
        {
            if (!File.Exists(basePath)) return false;
            resolved = Path.GetFullPath(basePath);
            return true;
        }

        foreach (var candidateExtension in new[] { ".exe", ".com", ".cmd", ".bat" })
        {
            var candidate = basePath + candidateExtension;
            if (!File.Exists(candidate)) continue;
            resolved = Path.GetFullPath(candidate);
            return true;
        }

        if (!File.Exists(basePath) || !HasPortableExecutableHeader(basePath)) return false;
        resolved = Path.GetFullPath(basePath);
        return true;
    }

    private static bool HasPortableExecutableHeader(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            return stream.ReadByte() == 'M' && stream.ReadByte() == 'Z';
        }
        catch
        {
            return false;
        }
    }

    private static string QuoteCommandArgument(string value)
    {
        if (value.Contains('"'))
            throw new InvalidOperationException("The Codex executable path contains an unsupported quote character.");
        return $"\"{value}\"";
    }

    private static InvalidOperationException CodexNotFound(string configured) => new(
        $"Codex CLI was not found (configured command: {configured}). Install it with 'npm install -g @openai/codex', then restart MultiCodex.");

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

    public sealed record LoginLaunch(
        string AccountName,
        CodexLoginMethod Method,
        ProcessStartInfo StartInfo);
}
