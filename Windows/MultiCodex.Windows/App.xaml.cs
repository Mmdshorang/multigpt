using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;

namespace MultiCodex.Windows;

public partial class App : System.Windows.Application
{
    private Forms.NotifyIcon? trayIcon;
    private MainWindow? mainWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        mainWindow = new MainWindow();
        MainWindow = mainWindow;
        mainWindow.Closing += (_, args) =>
        {
            if (!mainWindow.IsExiting)
            {
                args.Cancel = true;
                mainWindow.Hide();
            }
        };

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open MultiCodex", null, (_, _) => ShowWindow());
        menu.Items.Add("Refresh", null, async (_, _) => await mainWindow.RefreshAccountsAsync());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApp());

        trayIcon = new Forms.NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "MultiCodex",
            Visible = true,
            ContextMenuStrip = menu
        };
        trayIcon.DoubleClick += (_, _) => ShowWindow();
        mainWindow.Show();
    }

    private void ShowWindow()
    {
        if (mainWindow is null) return;
        mainWindow.Show();
        mainWindow.WindowState = WindowState.Normal;
        mainWindow.Activate();
    }

    private void ExitApp()
    {
        if (mainWindow is not null) mainWindow.IsExiting = true;
        if (trayIcon is not null)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
        }
        Shutdown();
    }
}
