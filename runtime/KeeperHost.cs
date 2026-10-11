using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// Windows GUI subsystem, no console. Watches process exit events only.
internal static class KeeperHost {
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
    static string root;
    static int restarts;
    static Process ExistingKeeper() {
        Process candidate = null;
        try {
            var row = Json.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(root, "keeper.state.private.json")));
            int pid = Convert.ToInt32(row["pid"]);
            using (var query = new ManagementObjectSearcher("SELECT CommandLine, ExecutablePath, CreationDate FROM Win32_Process WHERE ProcessId=" + pid)) {
                foreach (ManagementObject item in query.Get()) {
                    string command = Convert.ToString(item["CommandLine"]);
                    string executable = Convert.ToString(item["ExecutablePath"]);
                    if (!command.Contains(Path.Combine(root, "KeepAlive-LocalAssistant.ps1")) || !string.Equals(Path.GetFileName(executable), "powershell.exe", StringComparison.OrdinalIgnoreCase)) return null;
                    candidate = Process.GetProcessById(pid);
                    IntPtr handle = candidate.Handle;
                    if (Math.Abs((candidate.StartTime - ManagementDateTimeConverter.ToDateTime(Convert.ToString(item["CreationDate"]))).TotalSeconds) > 1) { candidate.Dispose(); return null; }
                    return candidate;
                }
            }
        } catch { if (candidate != null) candidate.Dispose(); }
        return null;
    }
    static void State(string mode, int worker) {
        var row = new Dictionary<string, object> {
            {"pid", Process.GetCurrentProcess().Id}, {"workerPid", worker},
            {"state", mode}, {"restarts", restarts}, {"at", DateTime.UtcNow.ToString("o")},
            {"mode", "native-no-console-process-events"}, {"hasConsole", GetConsoleWindow() != IntPtr.Zero}
        };
        string target = Path.Combine(root, "guardian.state.private.json");
        string tmp = target + ".tmp";
        File.WriteAllText(tmp, Json.Serialize(row), new UTF8Encoding(false));
        if (File.Exists(target)) File.Replace(tmp, target, null); else File.Move(tmp, target);
    }
    [STAThread] static int Main(string[] args) {
        root = Directory.GetParent(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)).FullName;
        if (args.Length == 1 && args[0] == "--self-test") { State("self-test", 0); return GetConsoleWindow() == IntPtr.Zero ? 0 : 2; }
        string suffix;
        using (var hash = SHA256.Create()) { suffix = BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(root.ToLowerInvariant()))).Replace("-", ""); }
        bool owned = false;
        using (var singleton = new Mutex(false, "Local\\ChatGPTLocalAssistant-Guardian-" + suffix)) {
            try { owned = singleton.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) return 0;
            try {
                using (var exit = new EventWaitHandle(false, EventResetMode.ManualReset, "Local\\ChatGPTLocalAssistant-" + suffix + "-Exit")) {
                    exit.Reset();
                    while (!exit.WaitOne(0)) {
                        Process child = null;
                        try {
                            string powershell = Path.Combine(Environment.GetEnvironmentVariable("WINDIR"), "System32\\WindowsPowerShell\\v1.0\\powershell.exe");
                            var start = new ProcessStartInfo(powershell, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + Path.Combine(root, "KeepAlive-LocalAssistant.ps1") + "\"") {
                                WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = true,
                                RedirectStandardOutput = true, RedirectStandardError = true
                            };
                            child = ExistingKeeper();
                            if (child == null) {
                                child = new Process { StartInfo = start, EnableRaisingEvents = true };
                                child.OutputDataReceived += delegate { }; child.ErrorDataReceived += delegate { };
                                child.Start(); child.BeginOutputReadLine(); child.BeginErrorReadLine();
                            }
                            State("watching", child.Id);
                            using (var exited = new EventWaitHandle(false, EventResetMode.ManualReset)) {
                                exited.SafeWaitHandle.Dispose();
                                exited.SafeWaitHandle = new Microsoft.Win32.SafeHandles.SafeWaitHandle(child.Handle, false);
                                int wake = WaitHandle.WaitAny(new WaitHandle[] { exited, exit });
                                if (wake == 1) { if (!child.WaitForExit(10000)) child.Kill(); break; }
                            }
                            restarts++; State("restarting", 0);
                            // Retry only after an actual worker exit, never a health poll.
                            if (exit.WaitOne(1000)) break;
                        } catch {
                            State("retrying", 0);
                            if (exit.WaitOne(5000)) break;
                        } finally { if (child != null) child.Dispose(); }
                    }
                    State("disabled", 0);
                }
                return 0;
            } catch { return 1; }
            finally { singleton.ReleaseMutex(); }
        }
    }
}
