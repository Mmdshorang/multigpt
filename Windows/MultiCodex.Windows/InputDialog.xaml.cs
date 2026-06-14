using System.Windows;

namespace MultiCodex.Windows;

public partial class InputDialog : Window
{
    public string Value => ValueBox.Text.Trim();

    public InputDialog()
    {
        InitializeComponent();
        Loaded += (_, _) => ValueBox.Focus();
    }

    private void Accept_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
    }
}
