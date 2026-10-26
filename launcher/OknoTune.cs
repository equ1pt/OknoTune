// OknoTune.exe: runs the newer of two scripts, the one embedded at build time or the latest release from GitHub.
// No internet or GitHub down: the embedded one runs. Built by build.ps1 with csc.exe from .NET Framework (C# 5).
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

static class Launcher
{
    const string Url = "https://github.com/equ1pt/OknoTune/releases/latest/download/OknoTune.ps1";

    static Version VersionOf(byte[] script)
    {
        if (script == null) return null;
        Match m = Regex.Match(Encoding.UTF8.GetString(script), @"\$script:Version = '([\d.]+)'");
        return m.Success ? new Version(m.Groups[1].Value) : null;
    }

    static byte[] Embedded()
    {
        using (Stream s = typeof(Launcher).Assembly.GetManifestResourceStream("OknoTune.ps1"))
        using (MemoryStream ms = new MemoryStream())
        {
            s.CopyTo(ms);
            return ms.ToArray();
        }
    }

    static byte[] Download()
    {
        try
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;   // TLS 1.2
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(Url);
            req.Timeout = 5000;
            req.ReadWriteTimeout = 5000;
            using (WebResponse resp = req.GetResponse())
            using (Stream s = resp.GetResponseStream())
            using (MemoryStream ms = new MemoryStream())
            {
                s.CopyTo(ms);
                return ms.ToArray();
            }
        }
        catch { return null; }
    }

    [STAThread]
    static int Main()
    {
        try
        {
            byte[] script = Embedded();
            Version local = VersionOf(script);
            byte[] remote = Download();
            Version remoteVer = VersionOf(remote);   // null for a captive-portal page or a cut-off file
            if (remoteVer != null && (local == null || remoteVer > local)) script = remote;

            string dir = Path.Combine(Path.GetTempPath(), "OknoTune");
            Directory.CreateDirectory(dir);
            string file = Path.Combine(dir, "OknoTune.ps1");
            File.WriteAllBytes(file, script);

            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -STA -File \"" + file + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process.Start(psi);
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show(e.Message, "OknoTune", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
