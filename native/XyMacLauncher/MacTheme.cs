using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;

namespace XyMacLauncher
{
    public sealed class DockAppEntry
    {
        public string Title;
        public string TargetPath;
        public string Arguments;
        public string ProcessHint;
        public string GlyphText;
        public Color TopColor;
        public Color BottomColor;
        public bool IsLaunchpad;
        public Image CachedIcon;
    }

    public static class MacTheme
    {
        private const int SW_HIDE = 0;
        private const int SW_SHOW = 5;

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        public static bool TaskbarHidden { get; private set; }

        public static void SetWindowsTaskbarHidden(bool hide)
        {
            try
            {
                IntPtr tray = FindWindow("Shell_TrayWnd", null);
                if (tray != IntPtr.Zero)
                {
                    ShowWindow(tray, hide ? SW_HIDE : SW_SHOW);
                    TaskbarHidden = hide;
                }
            }
            catch
            {
            }
        }

        public static GraphicsPath CreateRoundedRect(Rectangle bounds, int radius)
        {
            int d = Math.Max(2, radius * 2);
            GraphicsPath path = new GraphicsPath();
            path.AddArc(bounds.X, bounds.Y, d, d, 180, 90);
            path.AddArc(bounds.Right - d, bounds.Y, d, d, 270, 90);
            path.AddArc(bounds.Right - d, bounds.Bottom - d, d, d, 0, 90);
            path.AddArc(bounds.X, bounds.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        public static Bitmap RenderSquircleBadge(string text, Color top, Color bottom, int size)
        {
            Bitmap bmp = new Bitmap(size, size);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                Rectangle rect = new Rectangle(2, 2, size - 4, size - 4);
                using (GraphicsPath path = CreateRoundedRect(rect, size / 4))
                using (LinearGradientBrush brush = new LinearGradientBrush(rect, top, bottom, LinearGradientMode.Vertical))
                using (Pen border = new Pen(Color.FromArgb(95, 255, 255, 255), 1.4f))
                {
                    g.FillPath(brush, path);
                    g.DrawPath(border, path);
                }

                float fontSize = text.Length <= 2 ? size * 0.34f : size * 0.24f;
                using (Font font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel))
                using (StringFormat sf = new StringFormat())
                using (Brush white = new SolidBrush(Color.White))
                {
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    g.DrawString(text, font, white, new RectangleF(0, 1, size, size), sf);
                }
            }
            return bmp;
        }

        public static Image LoadOrRenderIcon(DockAppEntry item, int size)
        {
            try
            {
                if (!string.IsNullOrEmpty(item.TargetPath) && File.Exists(item.TargetPath) &&
                    item.TargetPath.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                {
                    Icon ico = Icon.ExtractAssociatedIcon(item.TargetPath);
                    if (ico != null)
                    {
                        Bitmap extracted = new Bitmap(size, size);
                        using (Graphics g = Graphics.FromImage(extracted))
                        {
                            g.SmoothingMode = SmoothingMode.AntiAlias;
                            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                            Rectangle bg = new Rectangle(2, 2, size - 4, size - 4);
                            using (GraphicsPath sq = CreateRoundedRect(bg, size / 4))
                            using (SolidBrush plate = new SolidBrush(Color.FromArgb(235, 28, 32, 42)))
                            using (Pen rim = new Pen(Color.FromArgb(75, 255, 255, 255), 1.2f))
                            {
                                g.FillPath(plate, sq);
                                g.DrawPath(rim, sq);
                            }
                            int pad = size / 6;
                            using (Bitmap raw = ico.ToBitmap())
                            {
                                g.DrawImage(raw, new Rectangle(pad, pad, size - pad * 2, size - pad * 2));
                            }
                        }
                        ico.Dispose();
                        return extracted;
                    }
                }
            }
            catch
            {
            }
            return RenderSquircleBadge(item.GlyphText, item.TopColor, item.BottomColor, size);
        }

        public static string DetectTailscaleIp()
        {
            try
            {
                NetworkInterface[] nics = NetworkInterface.GetAllNetworkInterfaces();
                for (int i = 0; i < nics.Length; i++)
                {
                    if (nics[i].OperationalStatus != OperationalStatus.Up) continue;
                    IPInterfaceProperties props = nics[i].GetIPProperties();
                    foreach (UnicastIPAddressInformation ua in props.UnicastAddresses)
                    {
                        if (ua.Address.AddressFamily == AddressFamily.InterNetwork)
                        {
                            byte[] b = ua.Address.GetAddressBytes();
                            if (b[0] == 100 && (b[1] & 0xC0) == 64)
                            {
                                return ua.Address.ToString();
                            }
                        }
                    }
                }
            }
            catch
            {
            }
            return "Tailscale Ready";
        }

        private static string FirstExisting(string[] candidates)
        {
            for (int i = 0; i < candidates.Length; i++)
            {
                if (!string.IsNullOrEmpty(candidates[i]) && File.Exists(candidates[i]))
                {
                    return candidates[i];
                }
            }
            return null;
        }

        public static List<DockAppEntry> BuildDefaultDockItems()
        {
            List<DockAppEntry> list = new List<DockAppEntry>();

            list.Add(new DockAppEntry
            {
                Title = "Finder (Explorer)",
                TargetPath = @"C:\Windows\explorer.exe",
                Arguments = "",
                ProcessHint = "explorer",
                GlyphText = "FD",
                TopColor = Color.FromArgb(56, 189, 248),
                BottomColor = Color.FromArgb(29, 78, 216)
            });

            list.Add(new DockAppEntry
            {
                Title = "Launchpad (Semua Aplikasi)",
                IsLaunchpad = true,
                GlyphText = "LP",
                TopColor = Color.FromArgb(168, 85, 247),
                BottomColor = Color.FromArgb(99, 102, 241)
            });

            string browser = FirstExisting(new string[] {
                @"C:\Program Files\Google\Chrome\Application\chrome.exe",
                @"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
            });
            list.Add(new DockAppEntry
            {
                Title = browser != null && browser.IndexOf("chrome", StringComparison.OrdinalIgnoreCase) >= 0 ? "Google Chrome" : "Browser",
                TargetPath = browser ?? @"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                Arguments = "",
                ProcessHint = browser != null && browser.IndexOf("chrome", StringComparison.OrdinalIgnoreCase) >= 0 ? "chrome" : "msedge",
                GlyphText = "WB",
                TopColor = Color.FromArgb(52, 211, 153),
                BottomColor = Color.FromArgb(5, 150, 105)
            });

            list.Add(new DockAppEntry
            {
                Title = "Downloads (Transfer HP <-> PC)",
                TargetPath = @"C:\Windows\explorer.exe",
                Arguments = "shell:Downloads",
                ProcessHint = "",
                GlyphText = "DL",
                TopColor = Color.FromArgb(59, 130, 246),
                BottomColor = Color.FromArgb(30, 64, 175)
            });

            list.Add(new DockAppEntry
            {
                Title = "Terminal (PowerShell)",
                TargetPath = @"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
                Arguments = "-NoLogo",
                ProcessHint = "powershell",
                GlyphText = ">_",
                TopColor = Color.FromArgb(55, 65, 81),
                BottomColor = Color.FromArgb(17, 24, 39)
            });

            string vscode = FirstExisting(new string[] {
                @"C:\Program Files\Microsoft VS Code\Code.exe",
                @"C:\Program Files (x86)\Microsoft VS Code\Code.exe"
            });
            if (vscode != null)
            {
                list.Add(new DockAppEntry
                {
                    Title = "Visual Studio Code",
                    TargetPath = vscode,
                    Arguments = "",
                    ProcessHint = "Code",
                    GlyphText = "VS",
                    TopColor = Color.FromArgb(14, 165, 233),
                    BottomColor = Color.FromArgb(2, 132, 199)
                });
            }

            string blender = FirstExisting(new string[] {
                @"C:\Studio\Blender\blender-4.2.3-windows-x64\blender.exe",
                @"C:\Games\Blender\blender-4.2.3-windows-x64\blender.exe",
                @"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
            });
            list.Add(new DockAppEntry
            {
                Title = "Blender 3D Studio",
                TargetPath = blender ?? @"C:\Studio\Blender\Launch-Blender.ps1",
                Arguments = "",
                ProcessHint = "blender",
                GlyphText = "3D",
                TopColor = Color.FromArgb(251, 146, 60),
                BottomColor = Color.FromArgb(194, 65, 12)
            });

            string rbxStudio = FirstExisting(new string[] {
                @"C:\Studio\RobloxStudio\RobloxStudioBeta.exe",
                @"C:\Games\Roblox\Studio\RobloxStudioBeta.exe"
            });
            list.Add(new DockAppEntry
            {
                Title = "Roblox Studio",
                TargetPath = rbxStudio ?? @"C:\Studio\RobloxStudio\RobloxStudioBeta.exe",
                Arguments = "",
                ProcessHint = "RobloxStudioBeta",
                GlyphText = "RS",
                TopColor = Color.FromArgb(56, 189, 248),
                BottomColor = Color.FromArgb(3, 105, 161)
            });

            string winrar = FirstExisting(new string[] {
                @"C:\Program Files\WinRAR\WinRAR.exe",
                @"C:\Program Files (x86)\WinRAR\WinRAR.exe"
            });
            list.Add(new DockAppEntry
            {
                Title = "WinRAR Archiver",
                TargetPath = winrar ?? @"C:\Program Files\7-Zip\7zFM.exe",
                Arguments = "",
                ProcessHint = "WinRAR",
                GlyphText = "RAR",
                TopColor = Color.FromArgb(192, 132, 252),
                BottomColor = Color.FromArgb(107, 33, 168)
            });

            list.Add(new DockAppEntry
            {
                Title = "Activity Monitor (Task Manager)",
                TargetPath = @"C:\Windows\System32\taskmgr.exe",
                Arguments = "",
                ProcessHint = "Taskmgr",
                GlyphText = "CPU",
                TopColor = Color.FromArgb(34, 197, 94),
                BottomColor = Color.FromArgb(21, 128, 61)
            });

            list.Add(new DockAppEntry
            {
                Title = "System Settings",
                TargetPath = @"C:\Windows\System32\control.exe",
                Arguments = "",
                ProcessHint = "",
                GlyphText = "CFG",
                TopColor = Color.FromArgb(148, 163, 184),
                BottomColor = Color.FromArgb(71, 85, 105)
            });

            for (int i = 0; i < list.Count; i++)
            {
                list[i].CachedIcon = LoadOrRenderIcon(list[i], 64);
            }
            return list;
        }

        public static void LaunchEntry(DockAppEntry entry)
        {
            if (entry == null) return;
            try
            {
                if (!string.IsNullOrEmpty(entry.TargetPath) && entry.TargetPath.EndsWith(".ps1", StringComparison.OrdinalIgnoreCase))
                {
                    if (File.Exists(entry.TargetPath))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = "powershell.exe",
                            Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + entry.TargetPath + "\"",
                            UseShellExecute = false
                        });
                    }
                    return;
                }
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = entry.TargetPath,
                    Arguments = entry.Arguments ?? "",
                    UseShellExecute = true
                };
                Process.Start(psi);
            }
            catch
            {
            }
        }
    }
}
