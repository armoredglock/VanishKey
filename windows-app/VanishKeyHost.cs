using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Diagnostics;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace VanishKeyHostApp
{
    public class MainForm : Form
    {
        private Process agentProcess;
        private PictureBox qrBox;
        private Label lblStatus;
        private Label lblDeviceId;
        private Label lblPin;
        private RichTextBox rtbLogs;
        private NotifyIcon trayIcon;
        private ContextMenuStrip trayMenu;
        private Panel statusDot;
        private Button btnStartStop;
        private Button btnEmergencyWipe;
        private Button btnOpenBrowser;
        private Button btnCopyPin;
        private Timer fileWatchTimer;
        private string agentDir;
        private string rootDir;
        private bool isExiting = false;

        [DllImport("user32.dll")]
        public static extern bool LockWorkStation();

        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }

        public MainForm()
        {
            // Determine working directories
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            if (Directory.Exists(Path.Combine(baseDir, "agent-cli")))
            {
                rootDir = baseDir;
                agentDir = Path.Combine(baseDir, "agent-cli");
            }
            else if (Directory.Exists(Path.Combine(baseDir, "..", "agent-cli")))
            {
                rootDir = Path.GetFullPath(Path.Combine(baseDir, ".."));
                agentDir = Path.Combine(rootDir, "agent-cli");
            }
            else
            {
                rootDir = @"D:\PROJECTS\VanishKey";
                agentDir = Path.Combine(rootDir, "agent-cli");
            }

            InitializeComponent();
            StartAgentProcess();
        }

        private void InitializeComponent()
        {
            this.Text = "VanishKey Desktop Host";
            this.Size = new Size(840, 580);
            this.MinimumSize = new Size(760, 520);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(10, 14, 26); // Obsidian #0A0E1A
            this.ForeColor = Color.White;
            this.Font = new Font("Segoe UI", 9.5f, FontStyle.Regular);

            // App Icon
            this.Icon = CreateAppIcon();

            // Setup System Tray
            trayMenu = new ContextMenuStrip();
            trayMenu.BackColor = Color.FromArgb(19, 27, 46);
            trayMenu.ForeColor = Color.White;
            trayMenu.Items.Add("Open VanishKey Host", null, (s, e) => RestoreFromTray());
            trayMenu.Items.Add("Emergency Wipe Now", null, (s, e) => TriggerEmergencyWipe());
            trayMenu.Items.Add("Restart Host", null, (s, e) => RestartAgent());
            trayMenu.Items.Add(new ToolStripSeparator());
            trayMenu.Items.Add("Exit", null, (s, e) => { isExiting = true; Application.Exit(); });

            trayIcon = new NotifyIcon();
            trayIcon.Text = "VanishKey Desktop Host (Active)";
            trayIcon.Icon = this.Icon;
            trayIcon.ContextMenuStrip = trayMenu;
            trayIcon.Visible = true;
            trayIcon.DoubleClick += (s, e) => RestoreFromTray();

            // 1. Top Header Bar
            Panel headerPanel = new Panel();
            headerPanel.Dock = DockStyle.Top;
            headerPanel.Height = 64;
            headerPanel.BackColor = Color.FromArgb(19, 27, 46); // Surface #131B2E
            headerPanel.Padding = new Padding(20, 0, 20, 0);

            Label titleLabel = new Label();
            titleLabel.Text = "VanishKey Desktop Host";
            titleLabel.Font = new Font("Segoe UI", 13f, FontStyle.Bold);
            titleLabel.ForeColor = Color.White;
            titleLabel.AutoSize = true;
            titleLabel.Location = new Point(20, 14);

            Label versionLabel = new Label();
            versionLabel.Text = "v1.2.0 • Ephemeral Access Guard";
            versionLabel.Font = new Font("Segoe UI", 8.5f, FontStyle.Regular);
            versionLabel.ForeColor = Color.FromArgb(148, 163, 184);
            versionLabel.AutoSize = true;
            versionLabel.Location = new Point(22, 38);

            // Status Pill Container (Right side of header)
            Panel statusPill = new Panel();
            statusPill.Size = new Size(210, 32);
            statusPill.Location = new Point(this.ClientSize.Width - 234, 16);
            statusPill.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            statusPill.BackColor = Color.FromArgb(15, 23, 42);

            statusDot = new Panel();
            statusDot.Size = new Size(10, 10);
            statusDot.Location = new Point(12, 11);
            statusDot.BackColor = Color.FromArgb(248, 113, 113); // Red by default

            lblStatus = new Label();
            lblStatus.Text = "Relay: Connecting...";
            lblStatus.ForeColor = Color.FromArgb(226, 232, 240);
            lblStatus.Font = new Font("Segoe UI", 8.5f, FontStyle.Bold);
            lblStatus.AutoSize = true;
            lblStatus.Location = new Point(28, 9);

            statusPill.Controls.Add(statusDot);
            statusPill.Controls.Add(lblStatus);

            headerPanel.Controls.Add(titleLabel);
            headerPanel.Controls.Add(versionLabel);
            headerPanel.Controls.Add(statusPill);

            // 2. Main Content Split Panel
            TableLayoutPanel mainLayout = new TableLayoutPanel();
            mainLayout.Dock = DockStyle.Fill;
            mainLayout.ColumnCount = 2;
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 320));
            mainLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            mainLayout.Padding = new Padding(16);

            // --- Left Panel: Device Info & QR Code ---
            Panel leftPanel = new Panel();
            leftPanel.Dock = DockStyle.Fill;
            leftPanel.BackColor = Color.FromArgb(19, 27, 46);
            leftPanel.Padding = new Padding(16);

            Label qrTitle = new Label();
            qrTitle.Text = "MOBILE PAIRING QR";
            qrTitle.Font = new Font("Segoe UI", 8.5f, FontStyle.Bold);
            qrTitle.ForeColor = Color.FromArgb(56, 189, 248); // Cyan
            qrTitle.Dock = DockStyle.Top;
            qrTitle.Height = 22;

            qrBox = new PictureBox();
            qrBox.Size = new Size(240, 240);
            qrBox.Location = new Point((320 - 32 - 240) / 2, 34);
            qrBox.SizeMode = PictureBoxSizeMode.Zoom;
            qrBox.BackColor = Color.White;
            qrBox.BorderStyle = BorderStyle.FixedSingle;

            lblDeviceId = new Label();
            lblDeviceId.Text = "Device ID: dev_win32_1677AA";
            lblDeviceId.Font = new Font("Consolas", 9f, FontStyle.Regular);
            lblDeviceId.ForeColor = Color.FromArgb(203, 213, 225);
            lblDeviceId.Location = new Point(14, 286);
            lblDeviceId.Size = new Size(260, 20);

            lblPin = new Label();
            lblPin.Text = "Pairing PIN: 795970";
            lblPin.Font = new Font("Consolas", 10f, FontStyle.Bold);
            lblPin.ForeColor = Color.FromArgb(56, 189, 248);
            lblPin.Location = new Point(14, 308);
            lblPin.Size = new Size(260, 22);

            btnCopyPin = CreateModernButton("Copy PIN", Color.FromArgb(15, 23, 42), Color.FromArgb(56, 189, 248));
            btnCopyPin.Location = new Point(14, 340);
            btnCopyPin.Size = new Size(125, 34);
            btnCopyPin.Click += (s, e) => {
                string pinText = lblPin.Text.Replace("Pairing PIN:", "").Trim();
                Clipboard.SetText(pinText);
                MessageBox.Show("Pairing PIN copied to clipboard!", "VanishKey", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            btnOpenBrowser = CreateModernButton("Browser QR", Color.FromArgb(15, 23, 42), Color.White);
            btnOpenBrowser.Location = new Point(148, 340);
            btnOpenBrowser.Size = new Size(125, 34);
            btnOpenBrowser.Click += (s, e) => {
                string htmlPath = Path.Combine(agentDir, "pairing-qr.html");
                if (File.Exists(htmlPath))
                {
                    Process.Start(new ProcessStartInfo(htmlPath) { UseShellExecute = true });
                }
            };

            leftPanel.Controls.Add(btnOpenBrowser);
            leftPanel.Controls.Add(btnCopyPin);
            leftPanel.Controls.Add(lblPin);
            leftPanel.Controls.Add(lblDeviceId);
            leftPanel.Controls.Add(qrBox);
            leftPanel.Controls.Add(qrTitle);

            // --- Right Panel: Live Logs & Controls ---
            Panel rightPanel = new Panel();
            rightPanel.Dock = DockStyle.Fill;
            rightPanel.Padding = new Padding(10, 0, 0, 0);

            Label logsTitle = new Label();
            logsTitle.Text = "LIVE AGENT ACTIVITY STREAM";
            logsTitle.Font = new Font("Segoe UI", 8.5f, FontStyle.Bold);
            logsTitle.ForeColor = Color.FromArgb(148, 163, 184);
            logsTitle.Dock = DockStyle.Top;
            logsTitle.Height = 22;

            rtbLogs = new RichTextBox();
            rtbLogs.Dock = DockStyle.Fill;
            rtbLogs.BackColor = Color.FromArgb(15, 23, 42); // #0F172A
            rtbLogs.ForeColor = Color.FromArgb(226, 232, 240);
            rtbLogs.Font = new Font("Consolas", 9.5f, FontStyle.Regular);
            rtbLogs.ReadOnly = true;
            rtbLogs.BorderStyle = BorderStyle.None;

            // Action Buttons Bar (Bottom of Right Panel)
            Panel bottomBar = new Panel();
            bottomBar.Dock = DockStyle.Bottom;
            bottomBar.Height = 52;
            bottomBar.Padding = new Padding(0, 10, 0, 0);

            btnStartStop = CreateModernButton("Restart Host", Color.FromArgb(2, 132, 199), Color.White);
            btnStartStop.Location = new Point(0, 10);
            btnStartStop.Size = new Size(130, 38);
            btnStartStop.Click += (s, e) => RestartAgent();

            btnEmergencyWipe = CreateModernButton("🛑 Force Wipe Guest Now", Color.FromArgb(220, 38, 38), Color.White);
            btnEmergencyWipe.Location = new Point(140, 10);
            btnEmergencyWipe.Size = new Size(185, 38);
            btnEmergencyWipe.Click += (s, e) => TriggerEmergencyWipe();

            Button btnTray = CreateModernButton("Minimize to Tray", Color.FromArgb(30, 41, 59), Color.FromArgb(203, 213, 225));
            btnTray.Location = new Point(335, 10);
            btnTray.Size = new Size(130, 38);
            btnTray.Click += (s, e) => MinimizeToTray();

            bottomBar.Controls.Add(btnStartStop);
            bottomBar.Controls.Add(btnEmergencyWipe);
            bottomBar.Controls.Add(btnTray);

            rightPanel.Controls.Add(rtbLogs);
            rightPanel.Controls.Add(bottomBar);
            rightPanel.Controls.Add(logsTitle);

            mainLayout.Controls.Add(leftPanel, 0, 0);
            mainLayout.Controls.Add(rightPanel, 1, 0);

            this.Controls.Add(mainLayout);
            this.Controls.Add(headerPanel);

            // Timer to periodically refresh QR code and config if updated
            fileWatchTimer = new Timer();
            fileWatchTimer.Interval = 2000;
            fileWatchTimer.Tick += (s, e) => RefreshQrCodeAndConfig();
            fileWatchTimer.Start();

            this.FormClosing += MainForm_FormClosing;
        }

        private Button CreateModernButton(string text, Color bg, Color fg)
        {
            Button btn = new Button();
            btn.Text = text;
            btn.BackColor = bg;
            btn.ForeColor = fg;
            btn.FlatStyle = FlatStyle.Flat;
            btn.FlatAppearance.BorderSize = 0;
            btn.Font = new Font("Segoe UI", 9f, FontStyle.Bold);
            btn.Cursor = Cursors.Hand;
            return btn;
        }

        private Icon CreateAppIcon()
        {
            using (Bitmap bmp = new Bitmap(32, 32))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using (Brush b = new SolidBrush(Color.FromArgb(2, 132, 199)))
                {
                    g.FillEllipse(b, 2, 2, 28, 28);
                }
                using (Pen p = new Pen(Color.FromArgb(56, 189, 248), 2.5f))
                {
                    g.DrawEllipse(p, 8, 8, 8, 8);
                    g.DrawLine(p, 16, 12, 24, 12);
                    g.DrawLine(p, 20, 12, 20, 16);
                    g.DrawLine(p, 23, 12, 23, 16);
                }
                return Icon.FromHandle(bmp.GetHicon());
            }
        }

        private void StartAgentProcess()
        {
            try
            {
                KillExistingAgent();

                string nodeExe = FindNodeExecutable();
                if (string.IsNullOrEmpty(nodeExe))
                {
                    AppendLog("[-] Error: Node.js executable not found in PATH.", Color.FromArgb(248, 113, 113));
                    return;
                }

                AppendLog("[*] Launching VanishKey Host Agent engine...", Color.FromArgb(56, 189, 248));

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = nodeExe;
                psi.Arguments = "src/index.js";
                psi.WorkingDirectory = agentDir;
                psi.EnvironmentVariables["RELAY_URL"] = "https://vanishkey-relay.onrender.com";
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;

                agentProcess = new Process();
                agentProcess.StartInfo = psi;
                agentProcess.EnableRaisingEvents = true;

                agentProcess.OutputDataReceived += (s, e) => {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        this.Invoke(new Action(() => ProcessAgentLog(e.Data)));
                    }
                };

                agentProcess.ErrorDataReceived += (s, e) => {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        this.Invoke(new Action(() => AppendLog("[-] " + e.Data, Color.FromArgb(248, 113, 113))));
                    }
                };

                agentProcess.Start();
                agentProcess.BeginOutputReadLine();
                agentProcess.BeginErrorReadLine();

                AppendLog("[+] Host engine initialized (PID: " + agentProcess.Id + ")", Color.FromArgb(34, 197, 94));
            }
            catch (Exception ex)
            {
                AppendLog("[-] Failed to start agent: " + ex.Message, Color.FromArgb(248, 113, 113));
            }
        }

        private string FindNodeExecutable()
        {
            string[] paths = {
                @"C:\Program Files\nodejs\node.exe",
                @"C:\Program Files (x86)\nodejs\node.exe",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\node\node.exe")
            };
            foreach (var p in paths)
            {
                if (File.Exists(p)) return p;
            }
            return "node.exe";
        }

        private void ProcessAgentLog(string line)
        {
            Color logColor = Color.FromArgb(226, 232, 240);

            if (line.Contains("[+] Connected to VanishKey Relay Server"))
            {
                logColor = Color.FromArgb(34, 197, 94);
                statusDot.BackColor = Color.FromArgb(34, 197, 94);
                lblStatus.Text = "Relay: Online";
            }
            else if (line.Contains("[i] Registered as pending pairing"))
            {
                logColor = Color.FromArgb(56, 189, 248);
                RefreshQrCodeAndConfig();
            }
            else if (line.Contains("DEVICE_PAIRED") || line.Contains("Device successfully paired"))
            {
                logColor = Color.FromArgb(34, 197, 94);
                trayIcon.ShowBalloonTip(3000, "VanishKey Paired!", "Your phone is now securely paired with this laptop.", ToolTipIcon.Info);
            }
            else if (line.Contains("Temporary Access Request") || line.Contains("Temporary user created"))
            {
                logColor = Color.FromArgb(251, 146, 60); // Orange
                trayIcon.ShowBalloonTip(3000, "Guest Access Active", "A temporary unprivileged guest account was generated.", ToolTipIcon.Info);
            }
            else if (line.Contains("Instant signout & purge") || line.Contains("forcefully signed out"))
            {
                logColor = Color.FromArgb(248, 113, 113); // Red
                trayIcon.ShowBalloonTip(3000, "Guest Purged", "The temporary account and files have been permanently wiped.", ToolTipIcon.Warning);
            }

            AppendLog(line, logColor);
        }

        private void AppendLog(string message, Color color)
        {
            if (this.IsDisposed || rtbLogs.IsDisposed) return;

            string time = DateTime.Now.ToString("HH:mm:ss");
            rtbLogs.SelectionStart = rtbLogs.TextLength;
            rtbLogs.SelectionLength = 0;
            rtbLogs.SelectionColor = Color.FromArgb(100, 116, 139);
            rtbLogs.AppendText("[" + time + "] ");

            rtbLogs.SelectionStart = rtbLogs.TextLength;
            rtbLogs.SelectionLength = 0;
            rtbLogs.SelectionColor = color;
            rtbLogs.AppendText(message + "\n");
            rtbLogs.ScrollToCaret();
        }

        private void RefreshQrCodeAndConfig()
        {
            try
            {
                string qrPath = Path.Combine(agentDir, "pairing-qr.png");
                if (File.Exists(qrPath))
                {
                    using (var fs = new FileStream(qrPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                    {
                        var img = Image.FromStream(fs);
                        var old = qrBox.Image;
                        qrBox.Image = new Bitmap(img);
                        if (old != null) old.Dispose();
                    }
                }

                string cfgPath = Path.Combine(agentDir, "agent-config.json");
                if (File.Exists(cfgPath))
                {
                    string json = File.ReadAllText(cfgPath);
                    if (json.Contains("\"deviceId\""))
                    {
                        string devId = ExtractJsonValue(json, "deviceId");
                        string pin = ExtractJsonValue(json, "pairingSecret");
                        if (!string.IsNullOrEmpty(devId)) lblDeviceId.Text = "Device ID: " + devId;
                        if (!string.IsNullOrEmpty(pin)) lblPin.Text = "Pairing PIN: " + pin;
                    }
                }
            }
            catch { }
        }

        private string ExtractJsonValue(string json, string key)
        {
            int idx = json.IndexOf("\"" + key + "\"");
            if (idx == -1) return "";
            int start = json.IndexOf(":", idx);
            if (start == -1) return "";
            int q1 = json.IndexOf("\"", start);
            if (q1 == -1) return "";
            int q2 = json.IndexOf("\"", q1 + 1);
            if (q2 == -1) return "";
            return json.Substring(q1 + 1, q2 - q1 - 1);
        }

        private void TriggerEmergencyWipe()
        {
            var res = MessageBox.Show(
                "Are you sure you want to immediately terminate the guest session, lock this computer, and delete the guest account?",
                "Emergency Wipe Confirmation",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning
            );

            if (res == DialogResult.Yes)
            {
                AppendLog("[!] MANUAL EMERGENCY WIPE TRIGGERED...", Color.FromArgb(248, 113, 113));
                try
                {
                    string scriptPath = Path.Combine(rootDir, "scripts", "windows", "delete_temp_user.ps1");
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = "powershell.exe";
                    psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -Username VanishGuest";
                    psi.UseShellExecute = false;
                    psi.CreateNoWindow = true;
                    Process.Start(psi);

                    // Lock workstation immediately
                    LockWorkStation();

                    AppendLog("[+] Guest session wiped and workstation locked successfully.", Color.FromArgb(34, 197, 94));
                }
                catch (Exception ex)
                {
                    AppendLog("[-] Emergency wipe error: " + ex.Message, Color.FromArgb(248, 113, 113));
                }
            }
        }

        private void RestartAgent()
        {
            AppendLog("[*] Restarting Host Agent...", Color.FromArgb(56, 189, 248));
            StartAgentProcess();
        }

        private void MinimizeToTray()
        {
            this.Hide();
            trayIcon.ShowBalloonTip(2000, "VanishKey Active in Tray", "Host is running in the background to protect your laptop.", ToolTipIcon.Info);
        }

        private void RestoreFromTray()
        {
            this.Show();
            this.WindowState = FormWindowState.Normal;
            this.BringToFront();
        }

        private void KillExistingAgent()
        {
            try
            {
                if (agentProcess != null && !agentProcess.HasExited)
                {
                    agentProcess.Kill();
                    agentProcess.Dispose();
                    agentProcess = null;
                }
            }
            catch { }
        }

        private void MainForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (!isExiting && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                MinimizeToTray();
                return;
            }

            fileWatchTimer.Stop();
            KillExistingAgent();
            if (trayIcon != null)
            {
                trayIcon.Visible = false;
                trayIcon.Dispose();
            }
        }
    }
}
