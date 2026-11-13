using System;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;

namespace XyMacLauncher
{
    public sealed class MacTopBarForm : Form
    {
        private readonly Label statusRightLabel;
        private readonly Timer clockTimer;
        private readonly Action openLaunchpadAction;
        private readonly Action quitLauncherAction;

        public MacTopBarForm(Action onOpenLaunchpad, Action onQuitLauncher)
        {
            this.openLaunchpadAction = onOpenLaunchpad;
            this.quitLauncherAction = onQuitLauncher;

            Rectangle screen = Screen.PrimaryScreen.Bounds;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.Bounds = new Rectangle(screen.Left, screen.Top, screen.Width, 28);
            this.BackColor = Color.FromArgb(18, 21, 30);
            this.ForeColor = Color.FromArgb(240, 243, 249);
            this.Opacity = 0.94;
            this.TopMost = true;
            this.ShowInTaskbar = false;
            this.DoubleBuffered = true;

            ContextMenuStrip appleMenu = new ContextMenuStrip();
            appleMenu.Items.Add("Tentang XyOS · Founder: xykal (Haekal Saputra) · XyVerse", null, delegate
            {
                MessageBox.Show(
                    "XyOS Mac-Style Desktop Launcher untuk XyRDP\n\n" +
                    "Founder : xykal (Haekal Saputra)\n" +
                    "Tim     : XyVerse Technology Global\n" +
                    "Lokasi  : Dikembangkan di Indonesia\n\n" +
                    "Klik 'Mode Taskbar Windows' kapan saja jika ingin beralih kembali ke taskbar klasik.",
                    "Tentang XyOS Launcher",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Information);
            });
            appleMenu.Items.Add(new ToolStripSeparator());
            appleMenu.Items.Add("Buka Launchpad", null, delegate { if (openLaunchpadAction != null) openLaunchpadAction(); });
            appleMenu.Items.Add("Sembunyikan / Tampilkan Taskbar Windows", null, delegate
            {
                MacTheme.SetWindowsTaskbarHidden(!MacTheme.TaskbarHidden);
                UpdateStatusText();
            });
            appleMenu.Items.Add(new ToolStripSeparator());
            appleMenu.Items.Add("Keluar dari XyMac Launcher (Kembali ke Windows Standar)", null, delegate
            {
                if (quitLauncherAction != null) quitLauncherAction();
            });

            FlowLayoutPanel leftFlow = new FlowLayoutPanel
            {
                Dock = DockStyle.Left,
                AutoSize = true,
                WrapContents = false,
                Padding = new Padding(10, 3, 0, 0),
                BackColor = Color.Transparent
            };

            Label appleBtn = CreateMenuLabel("\uF8FF  XyOS", true);
            appleBtn.Text = "\u2318 XyOS";
            appleBtn.Click += delegate { appleMenu.Show(appleBtn, new Point(0, appleBtn.Height)); };

            Label finderBtn = CreateMenuLabel("Finder", false);
            finderBtn.Click += delegate { TryStart("explorer.exe", ""); };

            Label launchpadBtn = CreateMenuLabel("Launchpad", false);
            launchpadBtn.Click += delegate { if (openLaunchpadAction != null) openLaunchpadAction(); };

            Label downloadsBtn = CreateMenuLabel("Downloads", false);
            downloadsBtn.Click += delegate { TryStart("explorer.exe", "shell:Downloads"); };

            Label terminalBtn = CreateMenuLabel("Terminal", false);
            terminalBtn.Click += delegate { TryStart("powershell.exe", "-NoLogo"); };

            Label modeToggleBtn = CreateMenuLabel("Taskbar Win", false);
            modeToggleBtn.Click += delegate
            {
                MacTheme.SetWindowsTaskbarHidden(!MacTheme.TaskbarHidden);
                UpdateStatusText();
            };

            leftFlow.Controls.Add(appleBtn);
            leftFlow.Controls.Add(finderBtn);
            leftFlow.Controls.Add(launchpadBtn);
            leftFlow.Controls.Add(downloadsBtn);
            leftFlow.Controls.Add(terminalBtn);
            leftFlow.Controls.Add(modeToggleBtn);

            statusRightLabel = new Label
            {
                Dock = DockStyle.Right,
                AutoSize = false,
                Width = 420,
                TextAlign = ContentAlignment.MiddleRight,
                Padding = new Padding(0, 0, 14, 0),
                Font = new Font("Segoe UI", 8.8f, FontStyle.Bold),
                ForeColor = Color.FromArgb(220, 228, 240),
                BackColor = Color.Transparent
            };

            this.Controls.Add(statusRightLabel);
            this.Controls.Add(leftFlow);

            UpdateStatusText();
            clockTimer = new Timer { Interval = 10000 };
            clockTimer.Tick += delegate { UpdateStatusText(); };
            clockTimer.Start();
        }

        private static Label CreateMenuLabel(string text, bool bold)
        {
            Label lbl = new Label
            {
                Text = text,
                AutoSize = true,
                Margin = new Padding(4, 2, 8, 2),
                Padding = new Padding(6, 2, 6, 2),
                Font = new Font("Segoe UI", 9f, bold ? FontStyle.Bold : FontStyle.Regular),
                ForeColor = Color.FromArgb(242, 245, 250),
                Cursor = Cursors.Hand
            };
            lbl.MouseEnter += delegate { lbl.BackColor = Color.FromArgb(45, 255, 255, 255); };
            lbl.MouseLeave += delegate { lbl.BackColor = Color.Transparent; };
            return lbl;
        }

        private static void TryStart(string file, string args)
        {
            try
            {
                Process.Start(new ProcessStartInfo { FileName = file, Arguments = args, UseShellExecute = true });
            }
            catch
            {
            }
        }

        private void UpdateStatusText()
        {
            string ts = MacTheme.DetectTailscaleIp();
            string mode = MacTheme.TaskbarHidden ? "Mac Full" : "Hybrid";
            string clock = DateTime.Now.ToString("ddd dd MMM  HH:mm");
            statusRightLabel.Text = string.Format("● {0}   |   {1}   |   {2}", ts, mode, clock);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen bottomLine = new Pen(Color.FromArgb(48, 255, 255, 255), 1f))
            {
                e.Graphics.DrawLine(bottomLine, 0, this.Height - 1, this.Width, this.Height - 1);
            }
        }
    }
}
