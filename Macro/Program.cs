using System.Text.Json;
using System.Runtime.InteropServices;

namespace Kd4kMacro;

internal sealed class MacroItem
{
    public string Name { get; set; } = "";
    public string Text { get; set; } = "";
}

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MacroForm());
    }
}

internal sealed class MacroForm : Form
{
    private const string AimWindowHint = "AIM";
    private const uint BmClick = 0x00F5;
    private const uint WmSetText = 0x000C;
    private readonly FlowLayoutPanel macroButtons = new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true, Padding = new Padding(8) };
    private readonly TextBox messageBox = new() { Multiline = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Font = new Font("Consolas", 11), BackColor = Color.FromArgb(20, 27, 32), ForeColor = Color.White };
    private readonly TextBox nameBox = new() { PlaceholderText = "Button label", Dock = DockStyle.Fill };
    private readonly TextBox textBox = new() { PlaceholderText = "Text to send", Dock = DockStyle.Fill };
    private readonly Label status = new() { AutoSize = true, ForeColor = Color.DarkSlateGray, Text = "Ready" };
    private List<MacroItem> macros = [];
    private string MacroFile => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "KD4K", "macros.json");

    public MacroForm()
    {
        Text = "KD4K AIM Macros";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(700, 420);
        Size = new Size(900, 560);
        BackColor = Color.FromArgb(239, 243, 244);
        BuildUi();
        LoadMacros();
        RenderMacros();
    }

    private void BuildUi()
    {
        var split = new SplitContainer { Dock = DockStyle.Fill, SplitterDistance = 260, Padding = new Padding(10) };
        var leftTitle = new Label { Text = "MACROS", Dock = DockStyle.Top, Height = 30, Font = new Font("Segoe UI", 11, FontStyle.Bold) };
        var rightTitle = new Label { Text = "MESSAGE TO AIM", Dock = DockStyle.Top, Height = 30, Font = new Font("Segoe UI", 11, FontStyle.Bold) };
        var send = new Button { Text = "Send to AIM", AutoSize = true };
        var clear = new Button { Text = "Clear", AutoSize = true };
        var add = new Button { Text = "Add macro", AutoSize = true };
        var reset = new Button { Text = "Reset defaults", AutoSize = true };
        var actions = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 38, FlowDirection = FlowDirection.LeftToRight };
        var editor = new TableLayoutPanel { Dock = DockStyle.Bottom, Height = 88, ColumnCount = 2, RowCount = 3 };

        editor.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 35));
        editor.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 65));
        editor.Controls.Add(new Label { Text = "New label", Anchor = AnchorStyles.Left }, 0, 0);
        editor.Controls.Add(nameBox, 1, 0);
        editor.Controls.Add(new Label { Text = "New text", Anchor = AnchorStyles.Left }, 0, 1);
        editor.Controls.Add(textBox, 1, 1);
        editor.Controls.Add(add, 1, 2);
        actions.Controls.Add(send);
        actions.Controls.Add(clear);
        actions.Controls.Add(status);
        split.Panel1.Controls.Add(macroButtons);
        split.Panel1.Controls.Add(leftTitle);
        split.Panel1.Controls.Add(editor);
        split.Panel1.Controls.Add(reset);
        split.Panel2.Controls.Add(messageBox);
        split.Panel2.Controls.Add(rightTitle);
        split.Panel2.Controls.Add(actions);
        Controls.Add(split);

        add.Click += (_, _) => AddMacro();
        reset.Click += (_, _) => { macros = DefaultMacros(); SaveMacros(); RenderMacros(); };
        clear.Click += (_, _) => messageBox.Clear();
        send.Click += (_, _) => SendToAim();
    }

    private static List<MacroItem> DefaultMacros() =>
    [
        new() { Name = "CQ call", Text = "CQ CQ CQ de KD4K" },
        new() { Name = "Signal report", Text = "KD4K, your signal is 59" },
        new() { Name = "Thank you", Text = "Thanks for the contact, 73" }
    ];

    private void LoadMacros()
    {
        try
        {
            if (File.Exists(MacroFile))
                macros = JsonSerializer.Deserialize<List<MacroItem>>(File.ReadAllText(MacroFile)) ?? [];
        }
        catch { macros = []; }
        if (macros.Count == 0) macros = DefaultMacros();
    }

    private void SaveMacros()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(MacroFile)!);
        File.WriteAllText(MacroFile, JsonSerializer.Serialize(macros, new JsonSerializerOptions { WriteIndented = true }));
    }

    private void RenderMacros()
    {
        macroButtons.Controls.Clear();
        foreach (var macro in macros)
        {
            var button = new Button { Text = macro.Name, Tag = macro, Width = 220, Height = 42, TextAlign = ContentAlignment.MiddleLeft };
            button.Click += (_, _) => messageBox.AppendText(messageBox.TextLength == 0 ? macro.Text : " " + macro.Text);
            macroButtons.Controls.Add(button);
        }
    }

    private void AddMacro()
    {
        if (string.IsNullOrWhiteSpace(nameBox.Text) || string.IsNullOrWhiteSpace(textBox.Text)) return;
        macros.Add(new MacroItem { Name = nameBox.Text.Trim(), Text = textBox.Text.Trim() });
        SaveMacros();
        nameBox.Clear();
        textBox.Clear();
        RenderMacros();
    }

    private void SendToAim()
    {
        if (string.IsNullOrWhiteSpace(messageBox.Text)) return;
        try
        {
            var aim = FindAimWindow();
            if (aim == IntPtr.Zero) throw new InvalidOperationException("NetLogger AIM window was not found.");
            SetForegroundWindow(aim);

            var controls = new List<IntPtr>();
            EnumChildWindows(aim, (handle, _) => { controls.Add(handle); return true; }, IntPtr.Zero);
            var edit = controls.LastOrDefault(handle => GetClassName(handle) is "Edit" or "RichEdit20A" or "RichEdit50W");
            if (edit == IntPtr.Zero) throw new InvalidOperationException("AIM message box was not found.");
            SendMessage(edit, WmSetText, IntPtr.Zero, messageBox.Text);

            var sendButton = controls.FirstOrDefault(handle => GetClassName(handle) == "Button" && GetWindowText(handle).Contains("Send", StringComparison.OrdinalIgnoreCase));
            if (sendButton == IntPtr.Zero) throw new InvalidOperationException("AIM Send button was not found.");
            SendMessage(sendButton, BmClick, IntPtr.Zero, IntPtr.Zero);
            status.Text = "Sent to AIM";
            status.ForeColor = Color.DarkGreen;
        }
        catch (Exception error) when (error is InvalidOperationException or COMException)
        {
            status.Text = error.Message;
            status.ForeColor = Color.DarkRed;
        }
    }

    private static IntPtr FindAimWindow()
    {
        IntPtr found = IntPtr.Zero;
        EnumWindows((handle, _) =>
        {
            if (GetWindowText(handle).Contains(AimWindowHint, StringComparison.OrdinalIgnoreCase))
            {
                found = handle;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }

    private static string GetClassName(IntPtr handle)
    {
        var buffer = new System.Text.StringBuilder(256);
        GetClassName(handle, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private static string GetWindowText(IntPtr handle)
    {
        var buffer = new System.Text.StringBuilder(512);
        GetWindowText(handle, buffer, buffer.Capacity);
        return buffer.ToString();
    }

    private delegate bool WindowCallback(IntPtr handle, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr parent, WindowCallback callback, IntPtr parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr handle, System.Text.StringBuilder text, int maxLength);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr handle, System.Text.StringBuilder text, int maxLength);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr handle);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, string lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wParam, IntPtr lParam);
}
