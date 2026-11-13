using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace XyMacLauncher
{
    public sealed class LaunchpadForm : Form
    {
        private readonly FlowLayoutPanel gridPanel;
        private readonly TextBox searchBox;
        private readonly List<string> shortcutFiles = new List<string>();

        public LaunchpadForm()
        {
            this.FormBorderStyle = FormBorderStyle.None;
            this.WindowState = FormWindowState.Maximized;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(14, 17, 26);
            this.Opacity = 0.94;
            this.ShowInTaskbar = false;
            this.TopMost = true;
            this.KeyPreview = true;
            this.DoubleBuffered = true;

            Panel header = new Panel
            {
                Dock = DockStyle.Top,
                Height = 96,
                BackColor = Color.Transparent
            };

            Label title = new Label
            {
                Text = "XyOS Launchpad · Semua Aplikasi Desktop",
                ForeColor = Color.FromArgb(240, 244, 250),
                Font = new Font("Segoe UI", 15f, FontStyle.Bold),
                AutoSize = true,
                Location = new Point(42, 22)
            };

            searchBox = new TextBox
            {
                Width = 320,
                Font = new Font("Segoe UI", 11f),
                BackColor = Color.FromArgb(28, 33, 46),
                ForeColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle,
                Location = new Point(42, 56)
            };
            searchBox.TextChanged += delegate { PopulateShortcuts(searchBox.Text); };

            Button closeBtn = new Button
            {
                Text = "Tutup (Esc)",
                FlatStyle = FlatStyle.Flat,
                ForeColor = Color.White,
                BackColor = Color.FromArgb(40, 46, 62),
                Size = new Size(116, 34),
                Location = new Point(380, 52)
            };
            closeBtn.FlatAppearance.BorderColor = Color.FromArgb(80, 255, 255, 255);
            closeBtn.Click += delegate { this.Close(); };

            header.Controls.Add(title);
            header.Controls.Add(searchBox);
            header.Controls.Add(closeBtn);

            gridPanel = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                AutoScroll = true,
                Padding = new Padding(38, 18, 38, 90),
                BackColor = Color.Transparent
            };
            gridPanel.Click += delegate { this.Close(); };

            this.Controls.Add(gridPanel);
            this.Controls.Add(header);

            this.KeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Escape) this.Close();
            };

            ScanDesktopShortcuts();
            PopulateShortcuts("");
        }

        private void ScanDesktopShortcuts()
        {
            shortcutFiles.Clear();
            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string[] dirs = new string[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory)
            };
            for (int d = 0; d < dirs.Length; d++)
            {
                if (string.IsNullOrEmpty(dirs[d]) || !Directory.Exists(dirs[d])) continue;
                string[] lnks = Directory.GetFiles(dirs[d], "*.lnk");
                for (int i = 0; i < lnks.Length; i++)
                {
                    string name = Path.GetFileNameWithoutExtension(lnks[i]);
                    if (seen.Add(name))
                    {
                        shortcutFiles.Add(lnks[i]);
                    }
                }
            }
        }

        private void PopulateShortcuts(string query)
        {
            gridPanel.SuspendLayout();
            gridPanel.Controls.Clear();
            string q = (query ?? "").Trim();

            for (int i = 0; i < shortcutFiles.Count; i++)
            {
                string path = shortcutFiles[i];
                string label = Path.GetFileNameWithoutExtension(path);
                if (q.Length > 0 && label.IndexOf(q, StringComparison.OrdinalIgnoreCase) < 0)
                {
                    continue;
                }

                Button tile = new Button
                {
                    Width = 168,
                    Height = 108,
                    Margin = new Padding(12),
                    FlatStyle = FlatStyle.Flat,
                    BackColor = Color.FromArgb(26, 31, 44),
                    ForeColor = Color.FromArgb(238, 242, 248),
                    Font = new Font("Segoe UI", 9.5f, FontStyle.Bold),
                    Text = label,
                    TextAlign = ContentAlignment.BottomCenter,
                    Padding = new Padding(6, 8, 6, 10),
                    Cursor = Cursors.Hand
                };
                tile.FlatAppearance.BorderColor = Color.FromArgb(65, 255, 255, 255);
                string captured = path;
                tile.Click += delegate
                {
                    try
                    {
                        Process.Start(new ProcessStartInfo { FileName = captured, UseShellExecute = true });
                    }
                    catch
                    {
                    }
                    this.Close();
                };
                gridPanel.Controls.Add(tile);
            }
            gridPanel.ResumeLayout();
        }
    }
}
