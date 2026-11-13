using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace XyMacLauncher
{
    public sealed class MacDockForm : Form
    {
        private readonly List<DockAppEntry> items;
        private readonly HashSet<int> runningIndices = new HashSet<int>();
        private readonly Timer stateTimer;
        private MacTopBarForm topBar;
        private int hoveredIndex = -1;

        private const int ICON_BASE = 48;
        private const int ICON_GAP = 12;
        private const int DOCK_PAD_X = 18;

        public MacDockForm(bool hideWindowsTaskbarInitially)
        {
            this.items = MacTheme.BuildDefaultDockItems();
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.Manual;
            this.BackColor = Color.FromArgb(19, 23, 34);
            this.Opacity = 0.95;
            this.TopMost = true;
            this.ShowInTaskbar = false;
            this.DoubleBuffered = true;

            LayoutDockGeometry();
            ApplyRoundedRegion();

            if (hideWindowsTaskbarInitially)
            {
                MacTheme.SetWindowsTaskbarHidden(true);
            }

            topBar = new MacTopBarForm(OpenLaunchpad, SafeQuit);
            topBar.Show();

            ContextMenuStrip dockMenu = new ContextMenuStrip();
            dockMenu.Items.Add("Buka Launchpad (Semua Aplikasi)", null, delegate { OpenLaunchpad(); });
            dockMenu.Items.Add("Sembunyikan / Tampilkan Taskbar Windows", null, delegate
            {
                MacTheme.SetWindowsTaskbarHidden(!MacTheme.TaskbarHidden);
                LayoutDockGeometry();
            });
            dockMenu.Items.Add(new ToolStripSeparator());
            dockMenu.Items.Add("Tutup XyMac Launcher", null, delegate { SafeQuit(); });
            this.ContextMenuStrip = dockMenu;

            RefreshRunningDots();
            stateTimer = new Timer { Interval = 4000 };
            stateTimer.Tick += delegate { RefreshRunningDots(); };
            stateTimer.Start();

            Microsoft.Win32.SystemEvents.DisplaySettingsChanged += OnDisplayChanged;
        }

        private void OnDisplayChanged(object sender, EventArgs e)
        {
            LayoutDockGeometry();
            ApplyRoundedRegion();
            if (topBar != null && !topBar.IsDisposed)
            {
                Rectangle s = Screen.PrimaryScreen.Bounds;
                topBar.Bounds = new Rectangle(s.Left, s.Top, s.Width, 28);
            }
        }

        private void LayoutDockGeometry()
        {
            Rectangle area = MacTheme.TaskbarHidden ? Screen.PrimaryScreen.Bounds : Screen.PrimaryScreen.WorkingArea;
            int width = DOCK_PAD_X * 2 + items.Count * ICON_BASE + Math.Max(0, items.Count - 1) * ICON_GAP;
            int height = 78;
            int x = area.Left + (area.Width - width) / 2;
            int y = area.Bottom - height - 8;
            this.Bounds = new Rectangle(x, y, width, height);
        }

        private void ApplyRoundedRegion()
        {
            using (GraphicsPath p = MacTheme.CreateRoundedRect(new Rectangle(0, 0, this.Width, this.Height), 22))
            {
                this.Region = new Region(p);
            }
        }

        private void RefreshRunningDots()
        {
            runningIndices.Clear();
            for (int i = 0; i < items.Count; i++)
            {
                string hint = items[i].ProcessHint;
                if (string.IsNullOrEmpty(hint)) continue;
                try
                {
                    Process[] procs = Process.GetProcessesByName(hint);
                    if (procs != null && procs.Length > 0)
                    {
                        runningIndices.Add(i);
                    }
                }
                catch
                {
                }
            }
            this.Invalidate();
        }

        private Rectangle GetIconSlot(int index)
        {
            int x = DOCK_PAD_X + index * (ICON_BASE + ICON_GAP);
            int y = 16;
            return new Rectangle(x, y, ICON_BASE, ICON_BASE);
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int found = -1;
            for (int i = 0; i < items.Count; i++)
            {
                Rectangle slot = GetIconSlot(i);
                Rectangle hit = Rectangle.Inflate(slot, 4, 8);
                if (hit.Contains(e.Location))
                {
                    found = i;
                    break;
                }
            }
            if (found != hoveredIndex)
            {
                hoveredIndex = found;
                this.Cursor = found >= 0 ? Cursors.Hand : Cursors.Default;
                this.Invalidate();
            }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (hoveredIndex != -1)
            {
                hoveredIndex = -1;
                this.Invalidate();
            }
        }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            if (e.Button != MouseButtons.Left || hoveredIndex < 0 || hoveredIndex >= items.Count)
            {
                return;
            }
            DockAppEntry clicked = items[hoveredIndex];
            if (clicked.IsLaunchpad)
            {
                OpenLaunchpad();
            }
            else
            {
                MacTheme.LaunchEntry(clicked);
            }
        }

        private void OpenLaunchpad()
        {
            using (LaunchpadForm lp = new LaunchpadForm())
            {
                lp.ShowDialog(this);
            }
        }

        private void SafeQuit()
        {
            MacTheme.SetWindowsTaskbarHidden(false);
            Application.Exit();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= OnDisplayChanged;
            MacTheme.SetWindowsTaskbarHidden(false);
            base.OnFormClosing(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;

            Rectangle outer = new Rectangle(1, 1, this.Width - 3, this.Height - 3);
            using (GraphicsPath bgPath = MacTheme.CreateRoundedRect(outer, 22))
            using (LinearGradientBrush glass = new LinearGradientBrush(
                outer,
                Color.FromArgb(245, 30, 35, 50),
                Color.FromArgb(245, 16, 19, 28),
                LinearGradientMode.Vertical))
            using (Pen rim = new Pen(Color.FromArgb(78, 255, 255, 255), 1.3f))
            {
                g.FillPath(glass, bgPath);
                g.DrawPath(rim, bgPath);
            }

            for (int i = 0; i < items.Count; i++)
            {
                Rectangle slot = GetIconSlot(i);
                bool hovered = (i == hoveredIndex);
                Rectangle drawRect = hovered
                    ? new Rectangle(slot.X - 4, slot.Y - 7, slot.Width + 8, slot.Height + 8)
                    : slot;

                if (items[i].CachedIcon != null)
                {
                    g.DrawImage(items[i].CachedIcon, drawRect);
                }

                if (runningIndices.Contains(i))
                {
                    using (SolidBrush dot = new SolidBrush(Color.FromArgb(230, 248, 250, 252)))
                    {
                        g.FillEllipse(dot, slot.X + (slot.Width / 2) - 2, this.Height - 9, 5, 5);
                    }
                }

                if (hovered)
                {
                    string tip = items[i].Title;
                    using (Font f = new Font("Segoe UI", 8.2f, FontStyle.Bold))
                    {
                        SizeF sz = g.MeasureString(tip, f);
                        int tw = Math.Min(this.Width - 12, (int)sz.Width + 14);
                        int tx = Math.Max(6, Math.Min(this.Width - tw - 6, slot.X + (slot.Width - tw) / 2));
                        Rectangle tipRect = new Rectangle(tx, 1, tw, 17);
                        using (GraphicsPath tp = MacTheme.CreateRoundedRect(tipRect, 7))
                        using (SolidBrush tb = new SolidBrush(Color.FromArgb(235, 12, 14, 20)))
                        using (Brush tf = new SolidBrush(Color.White))
                        using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                        {
                            g.FillPath(tb, tp);
                            g.DrawString(tip, f, tf, tipRect, sf);
                        }
                    }
                }
            }
        }
    }
}
