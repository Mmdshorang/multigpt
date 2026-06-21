using System.Windows;

namespace MultiCodex.Windows;

public partial class InputDialog : Window
{
    public string Value => ValueBox.Text.Trim();

    public InputDialog(
        string title = "Account name",
        string prompt = "Choose a name for the current Codex login",
        string acceptText = "Add account")
    {
        InitializeComponent();
        Title = title;
        PromptText.Text = prompt;
        AcceptButton.Content = acceptText;
        Loaded += (_, _) => ValueBox.Focus();
        UpdateAcceptButton();
    }

    private void Accept_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(Value)) return;
        DialogResult = true;
    }

    private void ValueBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) =>
        UpdateAcceptButton();

    private void UpdateAcceptButton()
    {
        if (AcceptButton is null) return;
        AcceptButton.IsEnabled = !string.IsNullOrWhiteSpace(Value);
    }
}
