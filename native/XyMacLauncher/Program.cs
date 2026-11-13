using System;
using System.Threading;
using System.Windows.Forms;

namespace XyMacLauncher
{
    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            bool selfTest = false;
            bool hideTaskbar = false;

            if (args != null)
            {
                for (int i = 0; i < args.Length; i++)
                {
                    if (string.Equals(args[i], "--self-test", StringComparison.OrdinalIgnoreCase))
                    {
                        selfTest = true;
                    }
                    else if (string.Equals(args[i], "--hide-taskbar", StringComparison.OrdinalIgnoreCase))
                    {
                        hideTaskbar = true;
                    }
                }
            }

            if (selfTest)
            {
                var items = MacTheme.BuildDefaultDockItems();
                if (items == null || items.Count < 6)
                {
                    Console.Error.WriteLine("{\"engine\":\"XyMacLauncher-csharp\",\"self_test\":\"failed\"}");
                    return 2;
                }
                Console.WriteLine("{\"engine\":\"XyMacLauncher-csharp\",\"self_test\":\"ok\",\"dock_items\":" + items.Count + "}");
                return 0;
            }

            bool createdNew = false;
            using (Mutex singleInstance = new Mutex(true, "Local\\XyMacLauncher_SingleInstance", out createdNew))
            {
                if (!createdNew)
                {
                    return 0;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.ApplicationExit += delegate
                {
                    MacTheme.SetWindowsTaskbarHidden(false);
                };

                Application.Run(new MacDockForm(hideTaskbar));
            }
            return 0;
        }
    }
}
