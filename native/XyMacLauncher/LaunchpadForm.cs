using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Windows.Forms;

namespace XyMacLauncher
{
    // An optional overlay, never a replacement Windows shell. Esc always closes it.
    public sealed class LaunchpadForm : Form
    {
        private readonly FlowLayoutPanel gridPanel;
        private readonly TextBox searchBox;
        private readonly Label resultLabel;
        private readonly List<string> shortcutFiles = new List<string>();
        private readonly Timer entranceTimer;

        public LaunchpadForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            WindowState = FormWindowState.Maximized;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(15, 20, 33);
            Opacity = 0.01;
            ShowInTaskbar = false;
            TopMost = true;
            KeyPreview = true;
            DoubleBuffered = true;

            Panel header = new Panel { Dock = DockStyle.Top, Height = 150, BackColor = Color.Transparent };
            Label eyebrow = new Label {
                Text = "XYVERSE  /  XYOS", ForeColor = Color.FromArgb(155, 196, 255),
                Font = new Font("Segoe UI", 9f, FontStyle.Bold), AutoSize = true, Location = new Point(48, 28)
            };
            Label title = new Label {
                Text = "Your space. Your apps.", ForeColor = Color.FromArgb(245, 248, 255),
                Font = new Font("Segoe UI", 20f, FontStyle.Bold), AutoSize = true, Location = new Point(45, 48)
            };
            searchBox = new TextBox {
                Width = 320, Font = new Font("Segoe UI", 11f), BackColor = Color.FromArgb(37, 45, 63),
                ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle, Location = new Point(48, 103)
            };
            searchBox.TextChanged += delegate { PopulateShortcuts(searchBox.Text); };
            Button closeBtn = new Button {
                Text = "Tutup  /  Esc", FlatStyle = FlatStyle.Flat, ForeColor = Color.White,
                BackColor = Color.FromArgb(45, 55, 75), Size = new Size(116, 34), Location = new Point(385, 99), Cursor = Cursors.Hand
            };
            closeBtn.FlatAppearance.BorderColor = Color.FromArgb(94, 143, 181, 229);
            closeBtn.Click += delegate { Close(); };
            resultLabel = new Label {
                AutoSize = true, ForeColor = Color.FromArgb(173, 185, 207),
                Font = new Font("Segoe UI", 9f), Location = new Point(520, 108)
            };
            header.Controls.Add(eyebrow); header.Controls.Add(title); header.Controls.Add(searchBox);
            header.Controls.Add(closeBtn); header.Controls.Add(resultLabel);

            gridPanel = new FlowLayoutPanel {
                Dock = DockStyle.Fill, AutoScroll = true, Padding = new Padding(38, 15, 38, 90),
                BackColor = Color.FromArgb(21, 28, 43)
            };
            Controls.Add(gridPanel);
            Controls.Add(header);
            KeyDown += delegate(object sender, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Close(); };
            ScanShortcuts();
            PopulateShortcuts("");

            entranceTimer = new Timer { Interval = 16 };
            entranceTimer.Tick += delegate {
                Opacity = Math.Min(0.96, Opacity + 0.12);
                if (Opacity >= 0.96) entranceTimer.Stop();
            };
            Shown += delegate { entranceTimer.Start(); searchBox.Focus(); };
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            entranceTimer.Stop();
            entranceTimer.Dispose();
            base.OnFormClosed(e);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            Rectangle rect = ClientRectangle;
            if (rect.Width <= 0 || rect.Height <= 0) return;
            using (LinearGradientBrush brush = new LinearGradientBrush(rect,
                Color.FromArgb(28, 44, 68), Color.FromArgb(13, 18, 31), 55f))
                e.Graphics.FillRectangle(brush, rect);
        }

        private void ScanShortcuts()
        {
            shortcutFiles.Clear();
            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            string[] dirs = {
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory),
                Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms)
            };
            for (int i = 0; i < dirs.Length; i++) ScanDirectory(dirs[i], seen, 0);
            shortcutFiles.Sort(StringComparer.OrdinalIgnoreCase);
        }

        // Limit depth, avoid reparse-point loops and tolerate inaccessible folders.
        private void ScanDirectory(string dir, HashSet<string> seen, int depth)
        {
            if (depth > 8 || string.IsNullOrEmpty(dir) || !Directory.Exists(dir) || shortcutFiles.Count >= 3000) return;
            try {
                if ((File.GetAttributes(dir) & FileAttributes.ReparsePoint) != 0) return;
                foreach (string path in Directory.GetFiles(dir, "*.lnk")) {
                    if (shortcutFiles.Count >= 3000) break;
                    string name = Path.GetFileNameWithoutExtension(path);
                    if (seen.Add(name)) shortcutFiles.Add(path);
                }
                foreach (string child in Directory.GetDirectories(dir)) ScanDirectory(child, seen, depth + 1);
            } catch (UnauthorizedAccessException) { }
              catch (IOException) { }
        }

        // Lightweight local badges avoid network dependencies and keep every shortcut legible.
        private static Bitmap CreateAppBadge(string name)
        {
            Bitmap image = new Bitmap(44, 44);
            int hue = (StringComparer.OrdinalIgnoreCase.GetHashCode(name) & 0x7fffffff) % 3;
            Color top = hue == 0 ? Color.FromArgb(97, 147, 236) :
                hue == 1 ? Color.FromArgb(142, 113, 224) : Color.FromArgb(78, 170, 174);
            Color bottom = hue == 0 ? Color.FromArgb(51, 84, 166) :
                hue == 1 ? Color.FromArgb(80, 65, 157) : Color.FromArgb(39, 102, 122);
            using (Graphics g = Graphics.FromImage(image))
            using (GraphicsPath shape = MacTheme.CreateRoundedRect(new Rectangle(1, 1, 42, 42), 11))
            using (LinearGradientBrush gradient = new LinearGradientBrush(new Rectangle(0, 0, 44, 44), top, bottom, 90f))
            using (Pen edge = new Pen(Color.FromArgb(115, 255, 255, 255)))
            using (Font font = new Font("Segoe UI", 15f, FontStyle.Bold))
            using (StringFormat format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.FillPath(gradient, shape);
                g.DrawPath(edge, shape);
                string initial = string.IsNullOrWhiteSpace(name) ? "•" : name.Trim().Substring(0, 1).ToUpperInvariant();
                g.DrawString(initial, font, Brushes.White, new RectangleF(0, 0, 44, 44), format);
            }
            return image;
        }

        private void PopulateShortcuts(string query)
        {
            gridPanel.SuspendLayout();
            while (gridPanel.Controls.Count > 0) {
                Control old = gridPanel.Controls[0];
                gridPanel.Controls.RemoveAt(0);
                old.Dispose();
            }
            string q = (query ?? "").Trim();
            int count = 0;
            foreach (string path in shortcutFiles) {
                string label = Path.GetFileNameWithoutExtension(path);
                if (q.Length > 0 && label.IndexOf(q, StringComparison.OrdinalIgnoreCase) < 0) continue;
                count++;
                Button tile = new Button {
                    Width = 156, Height = 116, Margin = new Padding(10), FlatStyle = FlatStyle.Flat,
                    BackColor = Color.FromArgb(39, 51, 70), ForeColor = Color.FromArgb(238, 243, 252),
                    Font = new Font("Segoe UI", 9.5f, FontStyle.Bold), Text = label,
                    TextAlign = ContentAlignment.BottomCenter, Padding = new Padding(6, 8, 6, 12), Cursor = Cursors.Hand
                };
                tile.FlatAppearance.BorderColor = Color.FromArgb(91, 129, 159, 202);
                tile.FlatAppearance.MouseOverBackColor = Color.FromArgb(58, 76, 103);
                tile.Image = CreateAppBadge(label);
                tile.ImageAlign = ContentAlignment.TopCenter;
                tile.Disposed += delegate { if (tile.Image != null) tile.Image.Dispose(); };
                string captured = path;
                tile.Click += delegate {
                    try {
                        Process.Start(new ProcessStartInfo { FileName = captured, UseShellExecute = true });
                        Close();
                    } catch (Exception ex) {
                        MessageBox.Show("Tidak dapat membuka aplikasi: " + ex.Message, "XyOS", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                };
                gridPanel.Controls.Add(tile);
            }
            resultLabel.Text = count + " aplikasi";
            gridPanel.ResumeLayout();
        }
    }
}
