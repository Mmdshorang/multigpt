using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace MultiCodex.Windows;

public sealed class AccountModel : INotifyPropertyChanged
{
    private string fiveHour = "--";
    private string weekly = "--";
    private string status = "Ready";

    public required string Name { get; init; }
    public required bool IsCurrent { get; init; }
    public required bool HasAuth { get; init; }
    public string CurrentLabel => IsCurrent ? "CURRENT" : "";
    public string AuthLabel => HasAuth ? "Connected" : "Needs login";
    public string FiveHour { get => fiveHour; set => Set(ref fiveHour, value); }
    public string Weekly { get => weekly; set => Set(ref weekly, value); }
    public string Status { get => status; set => Set(ref status, value); }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Set(ref string field, string value, [CallerMemberName] string? propertyName = null)
    {
        if (field == value) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
