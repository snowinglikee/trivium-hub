// Trivium Hub.exe - roda o launcher (app\Launcher.ps1) dentro do próprio processo, sem abrir powershell.exe.
// (antes ele chamava "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden", padrão que antivírus marcam como suspeito)
// Compilar: build.cmd
using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("Trivium Hub")]
[assembly: System.Reflection.AssemblyDescription("PS2, PS3 and PS4 launcher (PCSX2, RPCS3, shadPS4)")]
[assembly: System.Reflection.AssemblyProduct("Trivium Hub")]
[assembly: System.Reflection.AssemblyCompany("Trivium Hub")]
[assembly: System.Reflection.AssemblyCopyright("Trivium Hub. Emulators: see app\\licencas")]
[assembly: System.Reflection.AssemblyVersion("1.3.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.3.0.0")]

static class Program
{
    [STAThread]
    static int Main()
    {
        string appDir = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app");
        string script = Path.Combine(appDir, "Launcher.ps1");
        if (!File.Exists(script))
        {
            // aberto de dentro do zip: o Windows copia só o .exe para a pasta temporária, sem a pasta app
            string temp = Path.GetFullPath(Path.GetTempPath()).TrimEnd('\\');
            bool inZip = AppDomain.CurrentDomain.BaseDirectory.StartsWith(temp, StringComparison.OrdinalIgnoreCase);
            if (inZip)
                MessageBox.Show("Extraia o zip antes de abrir.\n\nClique com o botão direito no Trivium Hub.zip > Extrair tudo... e abra o Trivium Hub.exe da pasta extraída.\n\n" +
                    "Extract the zip first: right-click Trivium Hub.zip > Extract All... and open Trivium Hub.exe from the extracted folder.",
                    "Trivium Hub", MessageBoxButtons.OK, MessageBoxIcon.Information);
            else
                MessageBox.Show("Arquivos do Trivium Hub não encontrados.\nA pasta \"app\" precisa ficar ao lado do Trivium Hub.exe.\n\n" +
                    "Trivium Hub files not found.\nThe \"app\" folder must stay next to Trivium Hub.exe.",
                    "Trivium Hub", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        Directory.SetCurrentDirectory(appDir);
        try
        {
            // a política de execução vale só para este processo (não muda nada no Windows)
            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = System.Threading.ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;   // a janela precisa da thread STA principal
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(script);
                    ps.Invoke();
                    if (ps.HadErrors && ps.Streams.Error.Count > 0) WriteLog(appDir, ps.Streams.Error);
                }
            }
        }
        catch (Exception ex)
        {
            string log = WriteLog(appDir, ex.ToString());
            MessageBox.Show("O Trivium Hub fechou por um erro. / Trivium Hub closed because of an error.\n\n" + ex.Message + "\n\nDetalhes / Details:\n" + log,
                "Trivium Hub", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        return 0;
    }

    static string WriteLog(string appDir, PSDataCollection<ErrorRecord> errors)
    {
        StringBuilder sb = new StringBuilder();
        foreach (ErrorRecord e in errors)
        {
            sb.AppendLine(e.ToString());
            if (e.InvocationInfo != null) sb.AppendLine(e.InvocationInfo.PositionMessage);
            sb.AppendLine();
        }
        return WriteLog(appDir, sb.ToString());
    }

    static string WriteLog(string appDir, string text)
    {
        string dir = Path.Combine(appDir, "cache");
        string file = Path.Combine(dir, "erros.log");
        try
        {
            Directory.CreateDirectory(dir);
            File.AppendAllText(file, "==== " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "\r\n" + text + "\r\n", Encoding.UTF8);
        }
        catch { }
        return file;
    }
}
