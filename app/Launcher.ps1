# Trivium Hub - launcher para PS2 (PCSX2), PS3 (RPCS3) e PS4 (shadPS4)
# Detecta o console pelo arquivo, aplica as configurações do jogo no emulador,
# liga as otimizações de desempenho do Windows e inicia o jogo.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type -Namespace PL -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);'

# só uma cópia aberta: duas gravariam a configuração uma por cima da outra. Abrir de novo só traz a janela para a frente.
# Quem reabre o launcher (atualização, idioma) marca TRIVIUM_REOPEN: a cópia nova espera a antiga fechar
$script:OneCopy = New-Object System.Threading.Mutex($false, 'Local\TriviumHub.Launcher')
$reopen = $env:TRIVIUM_REOPEN -eq '1'
$env:TRIVIUM_REOPEN = $null
$free = $false
try { $free = $script:OneCopy.WaitOne($(if ($reopen) { 15000 } else { 0 })) } catch [System.Threading.AbandonedMutexException] { $free = $true }
if (-not $free) {
    $me = [System.Diagnostics.Process]::GetCurrentProcess()
    foreach ($p in [System.Diagnostics.Process]::GetProcessesByName($me.ProcessName)) {
        if ($p.Id -eq $me.Id -or $p.MainWindowHandle -eq [IntPtr]::Zero) { continue }
        if ([PL.Win]::IsIconic($p.MainWindowHandle)) { [void][PL.Win]::ShowWindow($p.MainWindowHandle, 9) }
        [void][PL.Win]::SetForegroundWindow($p.MainWindowHandle)
    }
    return
}

# ---- idioma: o launcher é escrito em português; em inglês cada texto passa pelo dicionário app\idiomas\en.txt
# na hora em que aparece na tela (botões, rótulos, menus, dicas, avisos e caixas de mensagem)
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
namespace PL {
    public static class Lang {
        public static bool On;
        static readonly Dictionary<string, string> Words = new Dictionary<string, string>();
        static readonly List<KeyValuePair<Regex, string>> Patterns = new List<KeyValuePair<Regex, string>>();
        static readonly char[] Seps = { '\n', '•', '·', '|' };
        static readonly HashSet<string> Missed = new HashSet<string>();
        static string missFile;
        static bool busy;
        public static void Load(string file) {
            if (!File.Exists(file)) return;
            missFile = Environment.GetEnvironmentVariable("TRIVIUM_TR_LOG");
            foreach (string raw in File.ReadAllLines(file, Encoding.UTF8)) {
                string line = raw.TrimEnd();
                if (line.Length == 0 || line.StartsWith("#")) continue;
                int i = line.IndexOf(" => ");
                if (i < 0) continue;
                string a = line.Substring(0, i).Replace("\\n", "\n"), b = line.Substring(i + 4).Replace("\\n", "\n");
                if (a.StartsWith("re: ")) Patterns.Add(new KeyValuePair<Regex, string>(new Regex(a.Substring(4), RegexOptions.Singleline), b));
                else Words[a.Trim()] = b;
            }
            On = true;
        }
        public static string T(string s) {
            if (!On || string.IsNullOrEmpty(s)) return s;
            string t = s.Trim();
            string v;
            if (t.Length == 0) return s;
            if (Words.TryGetValue(t.Replace("\r\n", "\n"), out v)) return s.Replace(t, v);
            foreach (var p in Patterns) { if (p.Key.IsMatch(t)) return s.Replace(t, p.Key.Replace(t, p.Value)); }
            // texto montado de partes (várias linhas, "a  •  b", filtro "Nome|*.x"): traduz parte por parte
            foreach (char sep in Seps) {
                if (t.IndexOf(sep) < 0) continue;
                string[] parts = s.Split(sep);
                for (int i = 0; i < parts.Length; i++) parts[i] = T(parts[i]);
                return string.Join(sep.ToString(), parts);
            }
            Note(t);
            return s;
        }
        // só em teste (variável TRIVIUM_TR_LOG): guarda no arquivo o que ficou sem tradução
        static void Note(string t) {
            if (missFile == null || !Missed.Add(t)) return;
            try { File.AppendAllText(missFile, t + "\r\n", Encoding.UTF8); } catch { }
        }
        // traduz a janela e tudo o que for colocado nela depois (inclusive textos trocados enquanto o launcher roda)
        public static void Hook(Control c) {
            if (!On || c == null) return;
            Fix(c);
            c.TextChanged += (s, e) => Fix((Control)s);
            c.ControlAdded += (s, e) => Hook(e.Control);
            ComboBox box = c as ComboBox;
            if (box != null) box.DropDown += (s, e) => Fix((Control)s);   // itens colocados depois de a janela abrir
            if (c.ContextMenuStrip != null) HookMenu(c.ContextMenuStrip);
            foreach (Control k in c.Controls) Hook(k);
        }
        static void Fix(Control c) {
            // caixas de texto têm o que a pessoa digitou: nunca traduz
            if (busy || c is TextBoxBase) return;
            busy = true;
            try {
                string n = T(c.Text);
                if (n != c.Text) c.Text = n;
                ComboBox cb = c as ComboBox;
                if (cb != null) for (int i = 0; i < cb.Items.Count; i++) { string s = cb.Items[i] as string; if (s != null) { string n2 = T(s); if (n2 != s) cb.Items[i] = n2; } }
            } finally { busy = false; }
        }
        public static void HookMenu(ToolStrip m) {
            if (!On || m == null) return;
            ToolStripDropDown dd = m as ToolStripDropDown;
            if (dd != null) dd.Opening += (s, e) => FixItems(((ToolStrip)s).Items);
            FixItems(m.Items);
        }
        static void FixItems(ToolStripItemCollection items) {
            foreach (ToolStripItem it in items) { it.Text = T(it.Text); it.ToolTipText = T(it.ToolTipText); }
        }
        // caixas de mensagem traduzidas (mesmos parâmetros do MessageBox.Show)
        public static DialogResult Msg(string text) { return MessageBox.Show(T(text)); }
        public static DialogResult Msg(string text, string caption) { return MessageBox.Show(T(text), T(caption)); }
        public static DialogResult Msg(string text, string caption, MessageBoxButtons b) { return MessageBox.Show(T(text), T(caption), b); }
        public static DialogResult Msg(string text, string caption, MessageBoxButtons b, MessageBoxIcon i) { return MessageBox.Show(T(text), T(caption), b, i); }
        public static DialogResult Msg(IWin32Window owner, string text, string caption) { return MessageBox.Show(owner, T(text), T(caption)); }
        public static DialogResult Msg(IWin32Window owner, string text, string caption, MessageBoxButtons b) { return MessageBox.Show(owner, T(text), T(caption), b); }
        public static DialogResult Msg(IWin32Window owner, string text, string caption, MessageBoxButtons b, MessageBoxIcon i) { return MessageBox.Show(owner, T(text), T(caption), b, i); }
    }
}
'@
function L([string]$s) { return [PL.Lang]::T($s) }

# barra de título escura (a do Windows é branca e destoa do launcher); Windows 10 1809+ e 11
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace PL {
    public static class Dark {
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
        static void Set(IntPtr h) {
            int on = 1;
            // 20 = DWMWA_USE_IMMERSIVE_DARK_MODE; 19 nas versões antigas do Windows 10
            try { if (DwmSetWindowAttribute(h, 20, ref on, 4) != 0) DwmSetWindowAttribute(h, 19, ref on, 4); } catch { }
        }
        public static void Use(Form f) {
            f.HandleCreated += (s, e) => Set(((Form)s).Handle);
            if (f.IsHandleCreated) Set(f.Handle);
        }
    }
}
'@

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppVersion = '1.3.0'   # versão do Trivium Hub (comparada com a publicada para avisar de atualização)

# idioma antes de tudo, para a tela de abertura já sair traduzida
# "auto" segue o Windows (português se o Windows estiver em português, senão inglês)
$script:Lang = ''
try { if ((Test-Path -LiteralPath (Join-Path $Root 'config.json')) -and (Get-Content -LiteralPath (Join-Path $Root 'config.json') -Raw -Encoding UTF8) -match '"lang"\s*:\s*"(\w+)"') { $script:Lang = $Matches[1] } } catch {}
if ($script:Lang -notin 'pt', 'en') { $script:Lang = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'pt') { 'pt' } else { 'en' } }
if ($script:Lang -eq 'en') { [PL.Lang]::Load((Join-Path $Root 'idiomas\en.txt')) }

# ---- tela de abertura: aparece na hora e fica até a janela principal abrir
# Primeiro só um quadro escuro no tamanho e na cor da abertura animada, para ela entrar sem emenda.
# O desenho abaixo só aparece se a animação não puder rodar
$script:PlainSplash = $false
$splash = New-Object System.Windows.Forms.Form
$splash.FormBorderStyle = 'None'; $splash.StartPosition = 'Manual'; $splash.ShowInTaskbar = $false; $splash.TopMost = $true
$sb = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$sw = [math]::Min(1180, [math]::Max(620, [int][math]::Floor($sb.Width * .62))); $sh = [int][math]::Floor($sw * 9 / 16)
$splash.Bounds = New-Object System.Drawing.Rectangle(($sb.Left + [int](($sb.Width - $sw) / 2)), ($sb.Top + [int](($sb.Height - $sh) / 2)), $sw, $sh)
$splash.BackColor = [System.Drawing.Color]::FromArgb(4, 5, 14)
$splashIcon = Join-Path $Root 'icon.ico'
if (Test-Path $splashIcon) { try { $splash.Icon = New-Object System.Drawing.Icon($splashIcon) } catch {} }
$sp = New-Object System.Drawing.Drawing2D.GraphicsPath
$sp.AddArc(0, 0, 36, 36, 180, 90); $sp.AddArc($sw - 37, 0, 36, 36, 270, 90); $sp.AddArc($sw - 37, $sh - 37, 36, 36, 0, 90); $sp.AddArc(0, $sh - 37, 36, 36, 90, 90); $sp.CloseFigure()
$splash.Region = New-Object System.Drawing.Region($sp)
$splash.Add_Paint({
        if (-not $script:PlainSplash) { return }
        $sg = $_.Graphics
        $sg.SmoothingMode = 'AntiAlias'; $sg.TextRenderingHint = 'AntiAliasGridFit'
        $rc = $this.ClientRectangle
        $sg.FillRectangle((New-Object System.Drawing.Drawing2D.LinearGradientBrush($rc, [System.Drawing.Color]::FromArgb(40, 40, 52), [System.Drawing.Color]::FromArgb(16, 16, 20), 90)), $rc)
        # marca: três círculos em triângulo, um por console (PS2 azul, PS3 vermelho, PS4 verde)
        $cols = @([System.Drawing.Color]::FromArgb(120, 170, 255), [System.Drawing.Color]::FromArgb(255, 130, 130), [System.Drawing.Color]::FromArgb(110, 220, 170))
        $pts = @(@(230, 52), @(213, 81), @(247, 81))
        for ($i = 0; $i -lt 3; $i++) {
            $sg.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, $cols[$i]))), $pts[$i][0] - 17, $pts[$i][1] - 17, 34, 34)
        }
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'
        $sg.DrawString((L ('TRIVIUM HUB')), (New-Object System.Drawing.Font('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 112, 460, 50)), $sf)
        $sg.DrawString((L ('PS2   •   PS3   •   PS4')), (New-Object System.Drawing.Font('Segoe UI', 10.5)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 160, 175))), (New-Object System.Drawing.RectangleF(0, 162, 460, 24)), $sf)
        $sg.DrawString((L ('Carregando biblioteca...')), (New-Object System.Drawing.Font('Segoe UI', 9)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, 110, 125))), (New-Object System.Drawing.RectangleF(0, 208, 460, 20)), $sf)
        # faixa nas três cores embaixo
        for ($i = 0; $i -lt 3; $i++) { $sg.FillRectangle((New-Object System.Drawing.SolidBrush($cols[$i])), [int](460 / 3 * $i), 246, [int](460 / 3) + 1, 4) }
    })
$splash.Show(); $splash.Refresh()

# telas de carregamento animadas, desenhadas por código, sem nenhuma imagem de console. Separadas do resto:
# se isto falhar, valem a tela de abertura acima e o aviso simples de "Abrindo jogo"
$script:PlayFxOk = $false
try {
    Add-Type -ErrorAction Stop -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Threading;
using System.Windows.Forms;

namespace PL {
    // marca do Trivium Hub: um T que é um entroncamento de três caminhos, uma peça por console (mesmo desenho de stub\make-logo.ps1)
    public static class Emblem {
        static readonly Color[] Tint = { Color.FromArgb(70, 136, 255), Color.FromArgb(255, 70, 92), Color.FromArgb(44, 210, 140) };
        static readonly float[][] Shape = {
            new[] { -.98f, -.80f, -.055f, -.80f, -.055f, -.14f, -.30f, -.34f, -.82f, -.34f },
            new[] { .98f, -.80f, .055f, -.80f, .055f, -.14f, .30f, -.34f, .82f, -.34f },
            new[] { 0f, -.06f, .28f, -.27f, .28f, .62f, 0f, .96f, -.28f, .62f, -.28f, -.27f }
        };
        static readonly float[] Light = { 20f, 160f, 90f };
        public static void Piece(Graphics g, int i, float cx, float cy, float size) {
            float u = size / 2;
            var pts = new PointF[Shape[i].Length / 2];
            for (int k = 0; k < pts.Length; k++) pts[k] = new PointF(cx + Shape[i][k * 2] * u, cy + Shape[i][k * 2 + 1] * u);
            Color c = Tint[i], top = Color.FromArgb(c.R + (255 - c.R) * 42 / 100, c.G + (255 - c.G) * 42 / 100, c.B + (255 - c.B) * 42 / 100);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var p = new GraphicsPath()) {
                p.AddPolygon(pts);
                using (var br = new LinearGradientBrush(p.GetBounds(), top, c, Light[i])) g.FillPath(br, p);
            }
        }
        public static void Draw(Graphics g, float cx, float cy, float size) { for (int i = 0; i < 3; i++) Piece(g, i, cx, cy, size); }
    }

    // mode: 0 abertura do launcher; 2, 3, 4 = console do jogo que está abrindo
    public class PlayFx : Form {
        readonly int mode, maxMs;
        readonly string title, status, note;
        readonly Image cover;
        readonly Color accent;
        readonly Stopwatch clock = Stopwatch.StartNew();
        readonly System.Windows.Forms.Timer tick = new System.Windows.Forms.Timer();
        readonly float[] px, py, ps, pv, pp;
        readonly Font fTitle, fStatus, fNote;
        Bitmap back, tile, glow, words;
        readonly Bitmap[] blobs = new Bitmap[3];
        [System.Runtime.InteropServices.DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint p);
        [System.Runtime.InteropServices.DllImport("winmm.dll")] static extern uint timeEndPeriod(uint p);
        public static long Frames; public static double DrawMs;
        public static string IntroSound;
        System.Media.SoundPlayer intro;
        public static IntPtr SplashHandle { get { var f = splash; return f != null && f.IsHandleCreated ? f.Handle : IntPtr.Zero; } }
        static PlayFx splash;
        double fadeAt = -1;
        int beat;
        [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint f);
        public static string LastError;

        // some aos poucos, revelando o jogo por baixo
        public static void Fade(Form f) {
            var p = f as PlayFx;
            // a abertura sempre toca até o fim, mesmo se o launcher carregar antes
            if (p != null && !p.IsDisposed && p.fadeAt < 0) p.fadeAt = Math.Max(p.clock.Elapsed.TotalMilliseconds, p.mode == 0 ? 3300 : 0);
        }

        [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] static extern IntPtr GetLongPtr(IntPtr h, int i);
        [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] static extern IntPtr SetLongPtr(IntPtr h, int i, IntPtr v);
        // janela sem borda cobrindo o monitor; a placa não troca de modo, então a animação continua visível até aqui
        public static void MakeBorderless(IntPtr h) {
            var s = Screen.FromHandle(h).Bounds;
            long style = GetLongPtr(h, -16).ToInt64();
            style = (style & ~0x00CF0000L) | 0x80000000L;   // tira barra de título e bordas; WS_POPUP
            SetLongPtr(h, -16, new IntPtr(style));
            SetWindowPos(h, IntPtr.Zero, s.Left, s.Top, s.Width, s.Height, 0x0020 | 0x0040);   // recalcula o quadro e mostra
        }

        PlayFx(int mode, Rectangle area, bool round, string title, string status, string note, Image cover, Color accent, int maxMs) {
            this.mode = mode; this.title = title; this.status = status; this.note = note; this.accent = accent; this.maxMs = maxMs;
            // cópia própria: a capa original continua nas mãos do launcher
            if (cover != null) this.cover = new Bitmap(cover);
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
            StartPosition = FormStartPosition.Manual; Bounds = area; BackColor = Color.Black; Opacity = 0;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
            if (round) using (var p = Round(new RectangleF(0, 0, area.Width, area.Height), 18)) Region = new Region(p);
            float k = area.Height / 1080f;
            fTitle = new Font("Segoe UI Semibold", Math.Max(15f, (mode == 0 ? 136f : 34f) * k), GraphicsUnit.Pixel);
            fStatus = new Font("Segoe UI", Math.Max(12f, (mode == 0 ? 34f : 22f) * k), GraphicsUnit.Pixel);
            fNote = new Font("Segoe UI", Math.Max(11f, (mode == 0 ? 26f : 18f) * k), GraphicsUnit.Pixel);
            int n = 90; var r = new Random(7);
            px = new float[n]; py = new float[n]; ps = new float[n]; pv = new float[n]; pp = new float[n];
            for (int i = 0; i < n; i++) { px[i] = (float)r.NextDouble(); py[i] = (float)r.NextDouble(); ps[i] = (float)(.25 + r.NextDouble()); pv[i] = (float)(.25 + r.NextDouble()); pp[i] = (float)(r.NextDouble() * 6.28); }
            // 10 ms com resolução fina do Windows: sem isso o timer cai em 15,6 ou 31 ms, os 30 FPS de antes
            timeBeginPeriod(1);
            tick.Interval = 10;
            tick.Tick += delegate {
                double ms = clock.Elapsed.TotalMilliseconds;
                // o emulador em tela cheia também fica "sempre no topo": a animação retoma a frente enquanto durar
                if (mode != 0 && ++beat % 3 == 0) SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);   // sem mover, sem redimensionar, sem foco
                if (fadeAt >= 0 && ms >= fadeAt) {
                    double gone = (ms - fadeAt) / 450;
                    if (gone >= 1) { Close(); return; }
                    Opacity = 1 - gone;
                } else if (Opacity < 1) Opacity = Math.Min(1.0, ms / 220);
                if (maxMs > 0 && ms > maxMs) { Close(); return; }
                Invalidate(); Update();
            };
            if (mode != 0) Click += delegate { Close(); };
            else Click += delegate { fadeAt = clock.Elapsed.TotalMilliseconds; };   // um clique pula a abertura
            tick.Start();
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams { get { var c = base.CreateParams; c.ExStyle |= 0x08000000 | 0x80; return c; } }
        protected override void OnFormClosed(FormClosedEventArgs e) {
            tick.Stop(); tick.Dispose(); timeEndPeriod(1); FreeBake();
            if (cover != null) cover.Dispose();
            foreach (var b in new[] { back, tile, glow, words, blobs[0], blobs[1], blobs[2], named, flare, halos[0], halos[1], halos[2], orbs[0], orbs[1], orbs[2], parts[0], parts[1], parts[2], auras[0], auras[1], auras[2] }) if (b != null) b.Dispose();
            if (titlePath != null) titlePath.Dispose();
            fTitle.Dispose(); fStatus.Dispose(); fNote.Dispose();
            base.OnFormClosed(e);
        }

        public static Form ShowGame(int console, string title, string status, string note, Image cover, int argb, Rectangle area) {
            var f = new PlayFx(console, area, false, title, status, note, cover, Color.FromArgb(argb), 40000);
            // volta já com o primeiro quadro pronto e opaco: o emulador só nasce depois disto
            f.Show(); f.Update(); f.Opacity = 1;
            return f;
        }
        // a abertura roda noutra thread: enquanto o launcher carrega, a thread principal não desenha nada
        public static void StartSplash(string title, string sub, string status) {
            var t = new Thread(delegate() {
                var s = Screen.PrimaryScreen.Bounds;
                int w = Math.Min(1180, Math.Max(620, (int)(s.Width * .62))), h = w * 9 / 16;
                var f = new PlayFx(0, new Rectangle(s.Left + (s.Width - w) / 2, s.Top + (s.Height - h) / 2, w, h), true, title, sub, status, null, Color.White, 0);
                splash = f;
                Application.Run(f);
            });
            t.IsBackground = true; t.SetApartmentState(ApartmentState.STA); t.Start();
        }
        public static void CloseSplash() {
            var f = splash; splash = null;
            try { if (f != null && f.IsHandleCreated) f.BeginInvoke(new MethodInvoker(delegate { Fade(f); })); } catch { }
        }

        static GraphicsPath Round(RectangleF r, float rad) {
            var p = new GraphicsPath(); float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }

        void MakeBack(int w, int h) {
            Color a, b;
            if (mode == 2) { a = Color.FromArgb(3, 5, 22); b = Color.FromArgb(14, 30, 92); }
            else if (mode == 3) { a = Color.FromArgb(16, 2, 8); b = Color.FromArgb(104, 12, 28); }
            else if (mode == 4) { a = Color.FromArgb(2, 8, 28); b = Color.FromArgb(10, 60, 140); }
            else { a = Color.FromArgb(4, 5, 14); b = Color.FromArgb(24, 24, 58); }
            back = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(back)) {
                g.Clear(a);
                using (var p = new GraphicsPath()) {
                    p.AddEllipse(-w * .25f, -h * .1f, w * 1.5f, h * 1.5f);
                    using (var br = new PathGradientBrush(p)) {
                        br.CenterColor = b; br.SurroundColors = new[] { a }; br.CenterPoint = new PointF(w / 2f, h * .68f);
                        g.FillPath(br, p);
                    }
                }
            }
            // luz de borda suave, pronta: desenhar círculos transparentes a cada quadro custa caro e fica duro
            Color[] tints = mode == 0 ? new[] { Color.FromArgb(120, 170, 255), Color.FromArgb(255, 130, 130), Color.FromArgb(110, 220, 170) }
                : new[] { Color.FromArgb(90, 170, 255), Color.FromArgb(120, 200, 255), Color.FromArgb(70, 130, 255) };
            for (int i = 0; i < 3; i++) {
                blobs[i] = new Bitmap(160, 160, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using (var g = Graphics.FromImage(blobs[i]))
                using (var p = new GraphicsPath()) {
                    p.AddEllipse(0, 0, 160, 160);
                    using (var br = new PathGradientBrush(p)) {
                        br.CenterColor = Color.FromArgb(70, tints[i]); br.SurroundColors = new[] { Color.FromArgb(0, tints[i]) };
                        g.FillPath(br, p);
                    }
                }
            }
            if (mode != 0) { MakeFront(w, h); Bake(w, h); } else BakeIntro(w, h);
        }

        [System.Runtime.InteropServices.DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr h);
        [System.Runtime.InteropServices.DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr h, IntPtr o);
        [System.Runtime.InteropServices.DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
        [System.Runtime.InteropServices.DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr h);
        [System.Runtime.InteropServices.DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, uint op);
        [System.Runtime.InteropServices.DllImport("msimg32.dll")] static extern bool AlphaBlend(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, int sw, int sh, int blend);
        IntPtr dcA, dcB, bmpA, bmpB, oldA, oldB;

        // fundo pronto com luzes e brilho: redimensionar imagens grandes a cada quadro derrubava para 14 FPS.
        // Duas versões com as luzes em lugares diferentes, misturadas por AlphaBlend, dão o movimento por 1 ms
        void Bake(int w, int h) {
            float k = h / 1080f, ch = 440 * k, top = h * .17f;
            for (int v = 0; v < 2; v++) {
                using (var b = new Bitmap(back))
                using (var g = Graphics.FromImage(b)) {
                    g.InterpolationMode = InterpolationMode.HighQualityBilinear; g.SmoothingMode = SmoothingMode.AntiAlias;
                    if (mode == 4) for (int i = 0; i < 12; i++) {
                        float x = (px[i] + v * .17f * ps[i]) % 1f, y = (py[i] + v * .2f * pv[i]) % 1f, s = h * (.3f + ps[i] * .32f);
                        g.DrawImage(blobs[i % 3], x * w - s / 2, y * h - s / 2, s, s);
                    }
                    g.DrawImage(glow, w / 2f - glow.Width / 2f, top + ch / 2 - glow.Height / 2f);
                    IntPtr bm = b.GetHbitmap(Color.Black), dc = CreateCompatibleDC(IntPtr.Zero), was = SelectObject(dc, bm);
                    if (v == 0) { dcA = dc; bmpA = bm; oldA = was; } else { dcB = dc; bmpB = bm; oldB = was; }
                }
            }
        }

        void FreeBake() {
            if (dcA != IntPtr.Zero) { SelectObject(dcA, oldA); DeleteDC(dcA); DeleteObject(bmpA); dcA = IntPtr.Zero; }
            if (dcB != IntPtr.Zero) { SelectObject(dcB, oldB); DeleteDC(dcB); DeleteObject(bmpB); dcB = IntPtr.Zero; }
        }

        // capa, brilho e textos prontos: cada quadro só copia estas imagens
        void MakeFront(int w, int h) {
            float k = h / 1080f; int ch = (int)(440 * k), cw = (int)(ch * .75f), pad = (int)(110 * k);
            tile = new Bitmap(cw, ch, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(tile)) {
                g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                using (var p = Round(new RectangleF(0, 0, cw - 1, ch - 1), 16 * k)) {
                    g.SetClip(p);
                    if (cover != null) g.DrawImage(cover, 0, 0, cw, ch);
                    else using (var br = new SolidBrush(Color.FromArgb(40, 255, 255, 255))) g.FillRectangle(br, 0, 0, cw, ch);
                    g.ResetClip();
                    using (var pen = new Pen(Color.FromArgb(110, 255, 255, 255), Math.Max(1f, 2 * k))) g.DrawPath(pen, p);
                }
            }
            glow = new Bitmap(cw + pad * 2, ch + pad * 2, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(glow)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                for (int i = 14; i >= 1; i--) {
                    float o = pad * i / 14f;
                    using (var br = new SolidBrush(Color.FromArgb(9, accent)))
                    using (var p = Round(new RectangleF(pad - o, pad - o, cw + o * 2, ch + o * 2), 18 * k + o)) g.FillPath(br, p);
                }
            }
            words = new Bitmap(w, (int)(240 * k) + 40, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(words)) {
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                var fmt = new StringFormat { Alignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter };
                using (var shade = new SolidBrush(Color.FromArgb(150, 0, 0, 0))) g.DrawString(title, fTitle, shade, new RectangleF(w * .1f + 2, 2, w * .8f, 56 * k + 12), fmt);
                g.DrawString(title, fTitle, Brushes.White, new RectangleF(w * .1f, 0, w * .8f, 56 * k + 12), fmt);
                using (var br = new SolidBrush(Color.FromArgb(150, 255, 255, 255))) g.DrawString(note, fNote, br, new RectangleF(0, 120 * k, w, 30 * k), fmt);
            }
        }

        protected override void OnPaint(PaintEventArgs e) {
            long started = Stopwatch.GetTimestamp();
            try {
                int w = ClientSize.Width, h = ClientSize.Height;
                if (w < 10 || h < 10) return;
                if (back == null) MakeBack(w, h);
                var g = e.Graphics;
                g.CompositingQuality = CompositingQuality.HighSpeed; g.InterpolationMode = InterpolationMode.Bilinear;
                float t = (float)clock.Elapsed.TotalSeconds;
                if (dcA != IntPtr.Zero) {
                    IntPtr hdc = g.GetHdc();
                    try {
                        BitBlt(hdc, 0, 0, w, h, dcA, 0, 0, 0x00CC0020);
                        if (mode == 4 || mode == 0) AlphaBlend(hdc, 0, 0, w, h, dcB, 0, 0, w, h, (int)(127.5 + 127.5 * Math.Sin(t * (mode == 0 ? 1.1 : .55))) << 16);
                    } finally { g.ReleaseHdc(hdc); }
                } else g.DrawImageUnscaled(back, 0, 0);
                if (mode == 2) Towers(g, w, h, t);
                else if (mode == 3) Waves(g, w, h, t);
                else if (mode == 4) Motes(g, w, h, t, 80, Color.FromArgb(190, 225, 255));
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                if (mode == 0) Trio(g, w, h, t); else Front(g, w, h, t);
            } catch (Exception ex) { LastError = ex.ToString(); }
            DrawMs = DrawMs * .9 + (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency * .1; Frames++;
            // o som começa no primeiro quadro desenhado: assim o impacto bate com o clarão do logo
            if (mode == 0 && intro == null && !string.IsNullOrEmpty(IntroSound)) {
                try { intro = new System.Media.SoundPlayer(IntroSound); intro.Play(); } catch { IntroSound = null; }
            }
        }

        // torres de blocos que sobem e descem em perspectiva, sobre um chão escuro
        void Towers(Graphics g, int w, int h, float t) {
            float floor = h * .97f;
            for (int row = 0; row < 3; row++) {
                float depth = 1f - row * .26f, cell = h * .02f * depth, gap = cell * .3f;
                int cols = (int)(w / (cell * 3.1f)) + 1;
                for (int c = 0; c < cols; c++) {
                    float wave = (float)(Math.Sin(t * (.9 + row * .15) + c * .55 + row * 1.7) * .5 + .5);
                    int blocks = 1 + (int)((5 - row) * wave * wave + (c * 7 + row * 5) % 2);
                    float x = c * cell * 3.1f + row * cell;
                    for (int b = 0; b < blocks; b++) {
                        float y = floor - row * h * .045f - b * (cell + gap);
                        int alpha = (int)(Math.Max(0, 190 - b * 14) * depth * (b == blocks - 1 ? 1f : .62f));
                        using (var br = new SolidBrush(Color.FromArgb(Math.Max(8, alpha), 90, 150, 255))) g.FillRectangle(br, x, y, cell * 1.9f, cell);
                    }
                }
            }
            Motes(g, w, h, t, 40, Color.FromArgb(170, 205, 255));
        }

        // faixas de onda atravessando a tela
        void Waves(Graphics g, int w, int h, float t) {
            int steps = 56;
            for (int k = 0; k < 5; k++) {
                var top = new PointF[steps + 1]; var low = new PointF[steps + 1];
                float baseY = h * (.46f + k * .075f), amp = h * (.05f + k * .012f);
                for (int i = 0; i <= steps; i++) {
                    float x = w * i / (float)steps, u = i / (float)steps * 6.28f;
                    float y = baseY + amp * (float)(Math.Sin(u * 1.1 + t * (.45 + k * .07) + k * 1.3) + .45 * Math.Sin(u * 2.3 - t * .36 + k));
                    top[i] = new PointF(x, y);
                    low[i] = new PointF(x, y + h * (.09f + .04f * (float)Math.Sin(u + t * .3 + k)));
                }
                using (var p = new GraphicsPath()) {
                    p.AddLines(top); Array.Reverse(low); p.AddLines(low); p.CloseFigure();
                    using (var br = new SolidBrush(Color.FromArgb(26, 255, 120, 140))) g.FillPath(br, p);
                }
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var pen = new Pen(Color.FromArgb(120 - k * 14, 255, 205, 215), Math.Max(1f, h * .0016f))) g.DrawLines(pen, top);
                g.SmoothingMode = SmoothingMode.None;
            }
            Motes(g, w, h, t, 34, Color.FromArgb(255, 200, 210));
        }

        void Motes(Graphics g, int w, int h, float t, int count, Color c) {
            for (int i = 0; i < count && i < px.Length; i++) {
                float y = 1f - ((py[i] + t * .022f * pv[i]) % 1f);
                float x = px[i] + .012f * (float)Math.Sin(t * .5 + pp[i]);
                int a = (int)(55 + 150 * (.5 + .5 * Math.Sin(t * 1.6 * pv[i] + pp[i])) * Math.Min(1f, y * 4f));
                float s = Math.Max(1.5f, h * .0042f * ps[i]);
                using (var br = new SolidBrush(Color.FromArgb(Math.Min(255, a), c))) g.FillRectangle(br, x * w, y * h, s, s);
            }
        }

        void Spinner(Graphics g, float cx, float cy, float r, float t, Color c) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var track = new Pen(Color.FromArgb(44, 255, 255, 255), Math.Max(2f, r * .13f))) g.DrawEllipse(track, cx - r, cy - r, r * 2, r * 2);
            using (var pen = new Pen(c, Math.Max(2f, r * .13f))) {
                pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                g.DrawArc(pen, cx - r, cy - r, r * 2, r * 2, t * 300 % 360, 90 + 60 * (float)Math.Sin(t * 2.2));
            }
            g.SmoothingMode = SmoothingMode.None;
        }

        // capa do jogo no centro, com brilho que respira
        void Front(Graphics g, int w, int h, float t) {
            float k = h / 1080f, ch = 440 * k, cw = ch * .75f, cx = w / 2f, top = h * .17f;
            float e = Math.Min(1f, t / .6f); e = 1 - (1 - e) * (1 - e) * (1 - e);
            float sc = .9f + .1f * e;
            float dw = cw * sc, dh = ch * sc, dx = cx - dw / 2, dy = top + (ch - dh) / 2;
            if (e < 1) g.DrawImage(tile, dx, dy, dw, dh); else g.DrawImageUnscaled(tile, (int)(cx - tile.Width / 2f), (int)top);
            float ty = top + ch + 44 * k;
            g.DrawImageUnscaled(words, 0, (int)ty);
            string dots = new string('.', 1 + (int)(t * 1.6f) % 3);
            if (statusSize.IsEmpty) statusSize = g.MeasureString(status + "...", fStatus);
            var size = statusSize;
            float sy = ty + 74 * k, sw = 34 * k, sx = cx - (size.Width + sw) / 2;
            Spinner(g, sx + 12 * k, sy + size.Height / 2, Math.Max(8f, 12 * k), t, accent);
            using (var br = new SolidBrush(Color.FromArgb(230, 255, 255, 255))) g.DrawString(status + dots, fStatus, br, sx + sw, sy);
        }

        // abertura: três esferas, uma por console, girando e se juntando
        void Trio(Graphics g, int w, int h, float t) {
            float cx = w / 2f, cy = h * .34f, r = h * .058f, age = t - Impact;
            Warp(g, w, h, cx, cy, t, age);
            // brilho grande atrás do logo, respirando depois do impacto
            if (age > 0) g.DrawImageUnscaled(flare, (int)cx - flare.Width / 2, (int)cy - flare.Height / 2);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            // ondas de choque: fortes no impacto e depois uma a cada 1,7 s
            if (age > 0) for (int i = 0; i < 3; i++) {
                float p = Math.Min(1f, (age - i * .09f) / 1.15f);
                if (p > 0 && p < 1) {
                    float rad = r + EaseOut(p) * h * .72f;
                    using (var pen = new Pen(Color.FromArgb((int)(210 * (1 - p)), Cols[i]), Math.Max(1f, h * .007f * (1 - p)))) g.DrawEllipse(pen, cx - rad, cy - rad, rad * 2, rad * 2);
                }
                float q = ((age + i * .55f) / 1.7f) % 1f, soft = r * 1.8f + q * h * .5f;
                if (age > 1.1f) using (var pen = new Pen(Color.FromArgb((int)(52 * (1 - q)), Cols[i]), 1.5f)) g.DrawEllipse(pen, cx - soft, cy - soft, soft * 2, soft * 2);
            }
            // cometas vêm de fora em espiral, cada um com um rastro, e no impacto viram as três peças do logo
            if (age < .1f) for (int i = 0; i < 3; i++) {
                for (int s = 34; s >= 1; s--) {
                    PointF p = Comet(i, t - s * .009f, cx, cy, r, h);
                    float size = h * .15f * (1 - s / 38f);
                    g.DrawImage(halos[i], p.X - size / 2, p.Y - size / 2, size, size);
                }
                PointF c = Comet(i, t, cx, cy, r, h);
                float bump = .72f + .28f * Math.Min(1f, t / Impact);
                float hz = h * .24f * bump, oz = orbs[i].Width * bump;
                g.DrawImage(halos[i], c.X - hz / 2, c.Y - hz / 2, hz, hz);
                g.DrawImage(orbs[i], c.X - oz / 2, c.Y - oz / 2, oz, oz);
            }
            if (age > 0) {
                float size = parts[0].Width, join = EaseOut(age / .5f);
                for (int i = 0; i < 3; i++) {
                    float hx = i == 2 ? cx : cx + (i == 0 ? -1 : 1) * size * .24f, hy = i == 2 ? cy + size * .2f : cy - size * .26f;
                    g.DrawImageUnscaled(auras[i], (int)hx - auras[i].Width / 2, (int)hy - auras[i].Height / 2);
                }
                for (int i = 0; i < 3; i++) {
                    float dx = i == 2 ? 0 : (i == 0 ? -1 : 1) * (1 - join) * h * .26f, dy = (i == 2 ? 1 : -.45f) * (1 - join) * h * .26f;
                    g.DrawImageUnscaled(parts[i], (int)(cx - size / 2 + dx), (int)(cy - size / 2 + dy));
                }
            }
            // faíscas do impacto
            if (age > 0 && age < 1.7f) {
                float life = 1 - age / 1.7f;
                for (int i = 0; i < px.Length; i++) {
                    float d = (ps[i] + .15f) * h * .62f * (1 - (float)Math.Exp(-age * 2.8));
                    float x = cx + d * (float)Math.Cos(pp[i]), y = cy + d * (float)Math.Sin(pp[i]) + age * age * h * .05f;
                    float s = Math.Max(1.5f, h * .006f * pv[i] * life);
                    using (var br = new SolidBrush(Color.FromArgb((int)(255 * life * life), Light(Cols[i % 3])))) g.FillEllipse(br, x - s / 2, y - s / 2, s, s);
                }
            }
            // clarão branco, apagando rápido
            if (age > 0 && age < .55f) {
                float f = 1 - age / .55f;
                using (var br = new SolidBrush(Color.FromArgb((int)(235 * f * f), 255, 255, 255))) g.FillRectangle(br, 0, 0, w, h);
            }
            Letters(g, w, h, cx, t, age);
            g.SmoothingMode = SmoothingMode.None;
        }

        const float Impact = 1.05f;
        static readonly Color[] Cols = { Color.FromArgb(120, 170, 255), Color.FromArgb(255, 120, 125), Color.FromArgb(100, 225, 170) };
        static Color Light(Color c) { return Color.FromArgb((c.R + 255) / 2, (c.G + 255) / 2, (c.B + 255) / 2); }

        // posição de cada esfera no tempo: espiral até o triângulo do logo, depois flutua devagar
        static PointF Comet(int i, float t, float cx, float cy, float r, int h) {
            double home = -1.5708 + i * 2.0944;
            if (i == 1) home = -1.5708 - 2.0944;      // PS3 à esquerda e PS4 à direita, como na marca
            if (i == 2) home = -1.5708 + 2.0944;
            float u = Math.Max(0f, Math.Min(1f, t / Impact)), e = u * u * (3 - 2 * u);
            double a = home - (1 - e) * 6.2 + .1 * Math.Sin(Math.Max(0f, t - Impact) * .9);
            float rad = r * 1.08f + (1 - e) * h * .92f + (t > Impact ? r * .05f * (float)Math.Sin(t * 1.9 + i) : 0);
            return new PointF(cx + rad * (float)Math.Cos(a), cy + rad * (float)Math.Sin(a));
        }

        // estrelas passando em velocidade até o impacto; depois quase param
        void Warp(Graphics g, int w, int h, float cx, float cy, float t, float age) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float run = age < 0 ? .7f * t * t / Impact : .7f * Impact + .1f * (1 - (float)Math.Exp(-age * 3)) + age * .018f;
            float tail = age < 0 ? .018f + .09f * t / Impact : .004f + .06f * (float)Math.Exp(-age * 5);
            for (int i = 0; i < px.Length; i++) {
                float z = (py[i] + run * (.6f + pv[i] * .6f)) % 1f, far = z * z * h * 1.15f, near = Math.Max(0f, z - tail); near = near * near * h * 1.15f;
                float cs = (float)Math.Cos(pp[i] * 7), sn = (float)Math.Sin(pp[i] * 7);
                int al = (int)(230 * Math.Min(1f, z * 2.4f));
                if (al < 6) continue;
                using (var pen = new Pen(Color.FromArgb(al, Light(Cols[i % 3])), Math.Max(1f, h * .0024f * ps[i])))
                    g.DrawLine(pen, cx + near * cs, cy + near * sn, cx + far * cs, cy + far * sn);
            }
            g.SmoothingMode = SmoothingMode.None;
        }

        // nome, linha nas três cores, texto e barra
        void Letters(Graphics g, int w, int h, float cx, float t, float age) {
            if (widths == null) {
                widths = new float[title.Length];
                for (int i = 0; i < title.Length; i++) { widths[i] = g.MeasureString(title.Substring(i, 1), fTitle, 400, typo).Width; titleW += widths[i]; }
            }
            float lx = cx - titleW / 2, ly = h * .545f, reveal = age - .12f;
            bool done = reveal > .4f + title.Length * .05f;
            if (done && named == null) {
                named = new Bitmap((int)titleW + 6, fTitle.Height + 12, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using (var q = Graphics.FromImage(named)) {
                    q.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    float x = 2;
                    titlePath = new GraphicsPath();
                    for (int i = 0; i < title.Length; i++) {
                        q.DrawString(title.Substring(i, 1), fTitle, Brushes.White, x, 2, typo);
                        titlePath.AddString(title.Substring(i, 1), fTitle.FontFamily, (int)fTitle.Style, fTitle.Size, new PointF(lx + x - 2, ly), typo);
                        x += widths[i];
                    }
                }
            }
            if (named != null) g.DrawImageUnscaled(named, (int)lx - 2, (int)ly - 2);
            else for (int i = 0; i < title.Length; i++) {
                float e = EaseOut((reveal - i * .05f) / .34f);
                if (e > 0) using (var br = new SolidBrush(Color.FromArgb((int)(255 * e), 255, 255, 255))) g.DrawString(title.Substring(i, 1), fTitle, br, lx, ly + (1 - e) * h * .05f, typo);
                lx += widths[i];
            }
            // brilho colorido atravessando só as letras
            float sweep = ((t - 2.2f) % 2.6f) / .9f;
            if (t > 2.2f && sweep < 1 && titlePath != null) {
                var band = new RectangleF(cx - titleW / 2 - 120 + sweep * (titleW + 240), ly, 120, fTitle.Height + 8);
                using (var lb = new LinearGradientBrush(band, Color.Transparent, Color.Transparent, 0f)) {
                    var cb = new ColorBlend();
                    cb.Colors = new[] { Color.FromArgb(0, Cols[0]), Color.FromArgb(255, Cols[0]), Color.FromArgb(255, Cols[1]), Color.FromArgb(255, Cols[2]), Color.FromArgb(0, Cols[2]) };
                    cb.Positions = new[] { 0f, .3f, .5f, .7f, 1f };
                    lb.InterpolationColors = cb;
                    lb.WrapMode = WrapMode.TileFlipX;
                    var keep = g.Clip;
                    g.SetClip(band);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.FillPath(lb, titlePath);
                    g.Clip = keep; keep.Dispose();
                }
            }
            // linha abrindo a partir do centro
            float open = EaseOut((age - .5f) / .6f), ly2 = h * .725f, half = titleW * .5f * open;
            if (open > 0) for (int i = 0; i < 3; i++) {
                float a = cx - half + half * 2 * i / 3f;
                using (var br = new SolidBrush(Cols[i])) g.FillRectangle(br, a, ly2, half * 2 / 3f + 1, Math.Max(2f, h * .004f));
            }
            var fmt = new StringFormat { Alignment = StringAlignment.Center };
            float sub = EaseOut((age - .75f) / .45f);
            if (sub > 0) {
                using (var br = new SolidBrush(Color.FromArgb((int)(215 * sub), 255, 255, 255))) g.DrawString(status, fStatus, br, new RectangleF(0, h * .75f + (1 - sub) * 12, w, h * .08f), fmt);
                string dots = new string('.', 1 + (int)(t * 2.4f) % 3);
                using (var br = new SolidBrush(Color.FromArgb((int)(150 * sub), 255, 255, 255))) g.DrawString(note.TrimEnd('.') + dots, fNote, br, new RectangleF(0, h * .845f, w, h * .07f), fmt);
            }
            // barra nas três cores, sempre correndo
            float bar = h * .945f, x0 = w * .2f, wide = w * .6f;
            using (var br = new SolidBrush(Color.FromArgb(34, 255, 255, 255))) g.FillRectangle(br, x0, bar, wide, 3);
            for (int i = 0; i < 3; i++) {
                float p = (t * .55f + i / 3f) % 1f, bx = x0 + wide * p, bw = w * .15f * (float)Math.Sin(p * 3.14);
                float gz = h * .11f;
                g.DrawImage(halos[i], bx - gz / 2, bar + 1 - gz / 2, gz, gz);
                using (var br = new SolidBrush(Light(Cols[i]))) g.FillRectangle(br, bx - bw / 2, bar, bw, 3);
            }
        }

        float[] widths; float titleW; SizeF statusSize;
        Bitmap named, flare;
        GraphicsPath titlePath;
        readonly Bitmap[] halos = new Bitmap[3], orbs = new Bitmap[3], parts = new Bitmap[3], auras = new Bitmap[3];

        static Bitmap Glow(int size, Color c, int alpha) {
            var b = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(b))
            using (var p = new GraphicsPath()) {
                p.AddEllipse(0, 0, size, size);
                using (var br = new PathGradientBrush(p)) {
                    br.CenterColor = Color.FromArgb(alpha, c); br.SurroundColors = new[] { Color.FromArgb(0, c) };
                    var fall = new Blend(); fall.Factors = new[] { 0f, .1f, .34f, 1f }; fall.Positions = new[] { 0f, .4f, .75f, 1f };
                    br.Blend = fall;
                    g.FillPath(br, p);
                }
            }
            return b;
        }

        static Bitmap Sphere(int d, Color c) {
            var b = new Bitmap(d + 2, d + 2, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(b)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var p = new GraphicsPath()) {
                    p.AddEllipse(1, 1, d, d);
                    using (var br = new PathGradientBrush(p)) {
                        br.CenterPoint = new PointF(d * .36f, d * .32f); br.CenterColor = Light(c);
                        br.SurroundColors = new[] { Color.FromArgb(255, c.R * 2 / 3, c.G * 2 / 3, c.B * 2 / 3) };
                        g.FillPath(br, p);
                    }
                }
                using (var br = new SolidBrush(Color.FromArgb(120, 255, 255, 255))) g.FillEllipse(br, d * .24f, d * .16f, d * .26f, d * .18f);
            }
            return b;
        }

        // aurora: duas versões do fundo misturadas por AlphaBlend, como no PS4
        void BakeIntro(int w, int h) {
            int logo = Math.Max(64, (int)(h * .36f));
            for (int i = 0; i < 3; i++) {
                halos[i] = Glow(160, Cols[i], 190); orbs[i] = Sphere(Math.Max(16, (int)(h * .116f)), Cols[i]);
                parts[i] = new Bitmap(logo, logo, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using (var g = Graphics.FromImage(parts[i])) Emblem.Piece(g, i, logo / 2f, logo / 2f, logo * .96f);
                auras[i] = Glow(Math.Max(64, (int)(h * .32f)), Cols[i], 150);
            }
            flare = Glow(Math.Max(120, (int)(h * .8f)), Color.FromArgb(150, 170, 255), 74);
            for (int v = 0; v < 2; v++) {
                using (var b = new Bitmap(back))
                using (var g = Graphics.FromImage(b)) {
                    g.InterpolationMode = InterpolationMode.HighQualityBilinear;
                    for (int i = 0; i < 7; i++) {
                        float x = (px[i + v * 7] * 1.3f - .15f), y = py[i + v * 7], s = h * (.7f + ps[i] * .6f);
                        g.DrawImage(blobs[i % 3], x * w - s / 2, y * h - s / 2, s, s);
                    }
                    IntPtr bm = b.GetHbitmap(Color.Black), dc = CreateCompatibleDC(IntPtr.Zero), was = SelectObject(dc, bm);
                    if (v == 0) { dcA = dc; bmpA = bm; oldA = was; } else { dcB = dc; bmpB = bm; oldB = was; }
                }
            }
        }
        readonly StringFormat typo = new StringFormat(StringFormat.GenericTypographic) { FormatFlags = StringFormatFlags.MeasureTrailingSpaces };
        static float EaseOut(float x) { x = Math.Max(0f, Math.Min(1f, x)); float u = 1 - x; return 1 - u * u * u; }
    }
}
'@
    $script:PlayFxOk = $true
    [PL.PlayFx]::IntroSound = Join-Path $Root 'sons\abertura.wav'
    [PL.PlayFx]::StartSplash('TRIVIUM HUB', 'PS2   •   PS3   •   PS4', (L 'Carregando biblioteca...'))
    # só tira o quadro escuro quando a animação já desenhou
    $wait = [Diagnostics.Stopwatch]::StartNew()
    while ([PL.PlayFx]::Frames -lt 2 -and $wait.ElapsedMilliseconds -lt 1500) { Start-Sleep -Milliseconds 10 }
    $splash.Hide()
} catch {}
if (-not $script:PlayFxOk) {
    $script:PlainSplash = $true
    $splash.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 24)
    $sp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $sp.AddArc(0, 0, 28, 28, 180, 90); $sp.AddArc(431, 0, 28, 28, 270, 90); $sp.AddArc(431, 221, 28, 28, 0, 90); $sp.AddArc(0, 221, 28, 28, 90, 90); $sp.CloseFigure()
    $splash.Region = New-Object System.Drawing.Region($sp)
    $splash.Bounds = New-Object System.Drawing.Rectangle(($sb.Left + [int](($sb.Width - 460) / 2)), ($sb.Top + [int](($sb.Height - 250) / 2)), 460, 250)
    $splash.Refresh()
}

# modo TV: cada quadro é desenhado aqui, compilado; o PowerShell só entrega imagens prontas quando algo muda.
# Se isto falhar, Draw-TvMode continua desenhando tudo como antes
$script:TvStageOk = $false
try {
    Add-Type -ErrorAction Stop -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace PL {
    public static class TvStage {
        [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint p);
        [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint p);
        // fundo em tela cheia: BitBlt/AlphaBlend levam cerca de 1 ms; o GDI+ com transparência levava mais de 10
        [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr h);
        [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr h, IntPtr o);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
        [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr h);
        [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, uint op);
        [DllImport("msimg32.dll")] static extern bool AlphaBlend(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, int sw, int sh, int blend);
        sealed class Surface : IDisposable {
            public IntPtr Dc, Bmp, Prev; public int W, H;
            public Surface(Bitmap b) { W = b.Width; H = b.Height; Bmp = b.GetHbitmap(Color.Black); Dc = CreateCompatibleDC(IntPtr.Zero); Prev = SelectObject(Dc, Bmp); }
            public void Dispose() { SelectObject(Dc, Prev); DeleteDC(Dc); DeleteObject(Bmp); }
        }
        static Surface backS, oldS;
        static Bitmap backKey;
        static Form form;
        static readonly System.Windows.Forms.Timer tick = new System.Windows.Forms.Timer();
        static readonly Stopwatch clock = Stopwatch.StartNew();
        static Bitmap top, foot, info;
        static Bitmap[] small = new Bitmap[0], big = new Bitmap[0], bigSel = new Bitmap[0];
        static bool[] fav = new bool[0];
        static int count, index, m, cw, ch, gap, rowY, infoY, bottomY;
        static double offset, last, changeT = -9, enterT = -9;
        static float tabX = -1, tabW, toX, toW;
        static Color tabColor = Color.White;
        static bool running, settled = true, hires;
        static readonly float[] dx = new float[34], dy = new float[34], dv = new float[34], dp = new float[34], ds = new float[34];
        static Font starFont; static Brush starBrush;
        public static long Frames; public static double DrawMs; public static string LastError;

        public static void Attach(Form f, Font star, Brush starB) {
            form = f; starFont = star; starBrush = starB;
            var r = new Random(11);
            for (int i = 0; i < dx.Length; i++) { dx[i] = (float)r.NextDouble(); dy[i] = (float)r.NextDouble(); dv[i] = .012f + (float)r.NextDouble() * .03f; dp[i] = (float)r.NextDouble() * 6.28f; ds[i] = 2 + r.Next(3); }
            f.Paint += (s, e) => Draw(e.Graphics);
            tick.Interval = 10;
            tick.Tick += OnTick;
        }
        public static void Start(bool entering) {
            if (entering) enterT = clock.Elapsed.TotalSeconds;
            if (running) return;
            running = true; last = clock.Elapsed.TotalSeconds;
            if (!hires) { timeBeginPeriod(1); hires = true; }   // sem isto o Windows arredonda o timer para 15,6 ou 31 ms
            tick.Start();
        }
        public static void Stop() {
            running = false; tick.Stop();
            if (hires) { timeEndPeriod(1); hires = false; }
        }
        public static bool TakeSettled() { if (settled && !notified) { notified = true; return true; } return false; }
        static bool notified = true;

        public static void SetLayout(int margin, int coverW, int coverH, int coverGap, int row, int infoTop, int bottom) { m = margin; cw = coverW; ch = coverH; gap = coverGap; rowY = row; infoY = infoTop; bottomY = bottom; }
        public static void SetChrome(Bitmap topBar, Bitmap footer) { top = topBar; foot = footer; }
        public static void SetInfo(Bitmap b) { info = b; }
        public static void SetBack(Bitmap b) {
            if (b == backKey) return;
            backKey = b;
            if (oldS != null) oldS.Dispose();
            oldS = backS; backS = new Surface(b); changeT = clock.Elapsed.TotalSeconds;
        }
        public static void SetTab(float x, float w, int argb) { if (tabX < 0) { tabX = x; tabW = w; } toX = x; toW = w; tabColor = Color.FromArgb(argb); }
        public static void BeginTiles(int total) {
            count = total;
            if (small.Length != total) { small = new Bitmap[total]; big = new Bitmap[total]; bigSel = new Bitmap[total]; fav = new bool[total]; }
            else { Array.Clear(small, 0, total); Array.Clear(big, 0, total); Array.Clear(bigSel, 0, total); }
        }
        public static void SetTile(int i, Bitmap s, Bitmap b, Bitmap sel, bool favorite) { if (i >= 0 && i < count) { small[i] = s; big[i] = b; bigSel[i] = sel; fav[i] = favorite; } }
        public static void SetIndex(int i, bool jump) { index = i; if (jump) offset = i; else if (Math.Abs(i - offset) > .003) { settled = false; notified = false; } }

        static void OnTick(object sender, EventArgs e) {
            double now = clock.Elapsed.TotalSeconds, dt = Math.Min(.05, now - last); last = now;
            double d = index - offset;
            if (Math.Abs(d) >= .003) offset += d * (1 - Math.Exp(-dt * 13));
            else { offset = index; settled = true; }
            if (form != null && form.Visible) { form.Invalidate(); form.Update(); }
        }

        static GraphicsPath Round(float x, float y, float w, float h, float r) {
            var p = new GraphicsPath(); float d = r * 2;
            p.AddArc(x, y, d, d, 180, 90); p.AddArc(x + w - d, y, d, d, 270, 90);
            p.AddArc(x + w - d, y + h - d, d, d, 0, 90); p.AddArc(x, y + h - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }
        static double Ease(double x) { x = Math.Max(0, Math.Min(1, x)); return 1 - Math.Pow(1 - x, 3); }

        public static int HitGame(int px, int py) {
            for (int i = Math.Max(0, (int)Math.Floor(offset) - 1); i < count; i++) {
                float near = (float)Math.Max(0, 1 - Math.Abs(i - offset)), s = 1 + .16f * near;
                int w = (int)(cw * s), h = (int)(ch * s), x = (int)(m + (i - offset) * (cw + gap) + cw * .16 * Math.Max(0, Math.Min(1, i - offset))), y = (int)(rowY - (h - ch) / 2f + ch * .08f);
                if (px >= x && px < x + w && py >= y && py < y + h) return i;
                if (x > form.ClientSize.Width) break;
            }
            return -1;
        }

        public static void Draw(Graphics g) {
            long t0 = Stopwatch.GetTimestamp();
            try {
                int W = form.ClientSize.Width, H = form.ClientSize.Height;
                double now = clock.Elapsed.TotalSeconds;
                g.CompositingQuality = CompositingQuality.HighSpeed; g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.SmoothingMode = SmoothingMode.None; g.PixelOffsetMode = PixelOffsetMode.Half;
                double fade = Math.Min(1, (now - changeT) / .42);
                if (backS == null) g.Clear(Color.FromArgb(10, 10, 14));
                else {
                    IntPtr hdc = g.GetHdc();
                    try {
                        if (oldS != null && fade < 1) {
                            BitBlt(hdc, 0, 0, W, H, oldS.Dc, 0, 0, 0x00CC0020);
                            AlphaBlend(hdc, 0, 0, W, H, backS.Dc, 0, 0, backS.W, backS.H, (int)(255 * fade) << 16);
                        } else BitBlt(hdc, 0, 0, W, H, backS.Dc, 0, 0, 0x00CC0020);
                    } finally { g.ReleaseHdc(hdc); }
                }
                using (var b = new SolidBrush(Color.FromArgb(120, 255, 255, 255)))
                    for (int i = 0; i < dx.Length; i++) {
                        float y = 1f - (float)((dy[i] + now * dv[i]) % 1), x = dx[i] + .01f * (float)Math.Sin(now * .6 + dp[i]);
                        g.FillRectangle(b, x * W, y * H, ds[i], ds[i]);
                    }
                if (top != null) g.DrawImageUnscaled(top, 0, 0);
                if (foot != null) g.DrawImageUnscaled(foot, 0, bottomY);
                tabX += (toX - tabX) * .24f; tabW += (toW - tabW) * .24f;
                using (var b = new SolidBrush(tabColor)) g.FillRectangle(b, tabX, 66, tabW, 3);
                double enter = Ease((now - enterT) / .55), textIn = Ease((now - changeT) / .4);
                int rowNow = rowY + (int)((1 - enter) * 60);
                if (count > 0) {
                    int first = Math.Max(0, (int)Math.Floor(offset) - 1);
                    for (int i = first; i < count; i++) {
                        double near = Math.Max(0, 1 - Math.Abs(i - offset));
                        double s = 1 + .16 * near;
                        int w = (int)(cw * s), h = (int)(ch * s);
                        int x = (int)(m + (i - offset) * (cw + gap) + cw * .16 * Math.Max(0, Math.Min(1, i - offset)));
                        int y = (int)(rowNow - (h - ch) / 2f + ch * .08f);
                        if (x > W) break;
                        Bitmap img = near > .5 ? bigSel[i] : near > .01 ? big[i] : small[i];
                        if (img == null) img = small[i] ?? big[i] ?? bigSel[i];
                        if (img == null) continue;
                        if (near > .5) using (var sh = new SolidBrush(Color.FromArgb(90, 0, 0, 0))) g.FillRectangle(sh, x + 6, y + 12, w, h);
                        if (img.Width == w && img.Height == h) g.DrawImageUnscaled(img, x, y);
                        else { g.InterpolationMode = InterpolationMode.Bilinear; g.DrawImage(img, x, y, w, h); g.InterpolationMode = InterpolationMode.NearestNeighbor; }
                        if (i == index && near > .9) Shine(g, x, y, w, h, now);
                        if (fav[i]) g.DrawString("", starFont, starBrush, x + w - 40f, y + 10f);
                    }
                    if (info != null) {
                        int iy = infoY + (int)((1 - enter) * 60) + (int)((1 - textIn) * 22);
                        if (textIn >= 1) g.DrawImageUnscaled(info, 0, iy);
                        else using (var ia = new ImageAttributes()) {
                            var cm = new ColorMatrix(); cm.Matrix33 = (float)textIn; ia.SetColorMatrix(cm);
                            g.DrawImage(info, new Rectangle(0, iy, info.Width, info.Height), 0, 0, info.Width, info.Height, GraphicsUnit.Pixel, ia);
                        }
                    }
                } else if (info != null) g.DrawImageUnscaled(info, 0, infoY);
                if (enter < 1) using (var b = new SolidBrush(Color.FromArgb((int)(255 * (1 - enter)), 8, 8, 12))) g.FillRectangle(b, 0, 0, W, H);
            } catch (Exception ex) { LastError = ex.ToString(); }
            double ms = (Stopwatch.GetTimestamp() - t0) * 1000.0 / Stopwatch.Frequency;
            DrawMs = DrawMs * .9 + ms * .1; Frames++;
        }

        // contorno que respira e reflexo que passa pela capa a cada 4 s
        static void Shine(Graphics g, int x, int y, int w, int h, double now) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            double pulse = .5 + .5 * Math.Sin(now * 2.6);
            using (var pen = new Pen(Color.FromArgb(70 + (int)(130 * pulse), 255, 255, 255), 2.5f))
            using (var ring = Round(x - 3, y - 3, w + 6, h + 6, 16)) g.DrawPath(pen, ring);
            double sw = (now % 4) / .9;
            if (sw < 1) {
                var keep = g.Clip;
                using (var clip = Round(x, y, w, h, 12)) {
                    g.SetClip(clip, CombineMode.Intersect);
                    var band = new RectangleF((float)(x - w * .5 + sw * w * 2), y, w * .5f, h);
                    using (var lb = new LinearGradientBrush(band, Color.Transparent, Color.Transparent, 0f)) {
                        var cb = new ColorBlend();
                        cb.Colors = new[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(62, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) };
                        cb.Positions = new[] { 0f, .5f, 1f };
                        lb.InterpolationColors = cb;
                        g.FillRectangle(lb, band);
                    }
                }
                g.Clip = keep;
            }
            g.SmoothingMode = SmoothingMode.None;
        }
    }
}
'@
    $script:TvStageOk = $true
} catch {}

$ConfigPath = Join-Path $Root 'config.json'
$EmuRoot = Join-Path $Root 'emuladores'

$EmuKeys = @('pcsx2', 'rpcs3', 'shadps4')
$EmuInfo = @{
    pcsx2       = @{ label = 'PCSX2 (PS2)'; exe = 'pcsx2-qt.exe'; title = 'Selecione pcsx2-qt.exe'; filter = 'PCSX2|pcsx2*.exe|Executáveis|*.exe' }
    rpcs3       = @{ label = 'RPCS3 (PS3)'; exe = 'rpcs3.exe'; title = 'Selecione rpcs3.exe'; filter = 'RPCS3|rpcs3.exe|Executáveis|*.exe' }
    shadps4     = @{ label = 'shadPS4 (PS4)'; exe = 'shadPS4.exe'; title = 'Selecione shadPS4.exe (o emulador, não o QtLauncher)'; filter = 'shadPS4|shadps4*.exe|Executáveis|*.exe' }
}

# Ports nativos de PS4: o código do jogo roda direto na CPU (sem emular), bem mais leve que o shadPS4.
# Reconhecidos pelo Title ID ou pelo nome do jogo (PARAM.SFO). cfg/appdata: onde o port guarda a pasta do jogo.
# (nenhum no momento: todos os jogos de PS4 abrem no shadPS4)
$NativePorts = @()

# ---------------------------------------------------------------- configurações por jogo

$CommonDefs = @(
    @{ key = 'saturation'; label = 'Saturação das cores'; type = 'slider' },
    @{ key = 'volume'; label = 'Volume do jogo  (no jogo: teclas - e +)'; type = 'slider' },
    @{ key = 'fullscreen'; label = 'Tela cheia'; type = 'check' }
)
$CommonDefaults = @{ saturation = 0; volume = 100; autosave = 10; fullscreen = $true; highPriority = $true; powerPlan = $true; onlineDns = ''; aniso = 0 }

# blocos da tela de configurações; opção fora desta lista cai em "Outros"
$SettingGroups = @(
    @{ title = 'Gráficos'; keys = 'renderer', 'scale', 'aniso', 'anisoInfo', 'textures', 'wcb', 'fsr', 'neo', 'aspect', 'stretch' },
    @{ title = 'Desempenho'; keys = 'fps120', 'fps90', 'fps60', 'eeCycle', 'mtvu', 'fastCdvd', 'spuBlock', 'frameLimit', 'present', 'vsync', 'turbo', 'skipVideos', 'communityFix', 'officialEmu' },
    @{ title = 'Jogo e tela'; keys = 'language', 'fullscreen', 'saturation', 'volume', 'showFps', 'autosave' },
    @{ title = 'Online'; keys = @('onlineDns') }
)
$AnisoOptions = @(@('Desligado', 0), @('2x', 2), @('4x', 4), @('8x', 8), @('16x', 16))

$SettingDefs = @{
    PS2 = @(
        @{ key = 'renderer'; label = 'Renderizador'; type = 'combo'; options = @(
                @('Automático', -1), @('Vulkan', 14), @('Direct3D 11', 3), @('Direct3D 12', 15), @('OpenGL', 12), @('Software (lento)', 13)) },
        @{ key = 'scale'; label = 'Resolução interna'; type = 'combo'; options = @(
                @('1x Nativa (480p) - mais leve', 1), @('2x (720p)', 2), @('3x (1080p)', 3), @('4x (1440p)', 4), @('6x (4K)', 6)) },
        @{ key = 'aniso'; label = 'Filtro anisotrópico'; type = 'combo'; options = $AnisoOptions },
        @{ key = 'eeCycle'; label = 'Velocidade da CPU do PS2 (EE)'; type = 'combo'; options = @(
                @('-2  bem mais FPS (pode bugar)', -2), @('-1  mais FPS', -1), @('0  normal', 0), @('+1  mais precisão', 1)) },
        @{ key = 'mtvu'; label = 'Thread VU dedicada (MTVU) - mais FPS em CPU com 4+ núcleos'; type = 'check' },
        @{ key = 'textures'; label = 'Texturas HD (usa o pacote de texturas instalado, se houver)'; type = 'check' },
        @{ key = 'fastCdvd'; label = 'CD/DVD rápido (carregamentos mais curtos)'; type = 'check' },
        @{ key = 'aspect'; label = 'Tela'; type = 'combo'; options = @(
                @('Widescreen 16:9 sem bordas (recomendado)', 'widescreen'), @('Esticar na tela toda', 'stretch'), @('Original 4:3 (com bordas)', 'original')) },
        @{ key = 'fps60'; label = '60 FPS (patch da comunidade para este jogo)'; type = 'check'; cond = 'patch:fps60' },
        @{ key = 'onlineDns'; label = 'Jogar online: DNS (vazio = desligado)'; type = 'text' },
        @{ key = 'vsync'; label = 'VSync (sem tearing, pode reduzir FPS)'; type = 'check' },
        @{ key = 'showFps'; label = 'Mostrar FPS na tela'; type = 'check' },
        @{ key = 'turbo'; label = 'Avanço rápido (segure PS/Xbox ou Tab)'; type = 'combo'; options = @(
                @('2x mais rápido', 2), @('3x mais rápido', 3), @('4x mais rápido', 4)) },
        @{ key = 'autosave'; label = 'Save automático (protege contra crash)'; type = 'combo'; options = @(
                @('A cada 5 minutos', 5), @('A cada 10 minutos', 10), @('A cada 15 minutos', 15), @('Desligado', 0)) }
    )
    PS3 = @(
        @{ key = 'renderer'; label = 'Renderizador'; type = 'combo'; options = @(@('Vulkan', 'Vulkan'), @('OpenGL', 'OpenGL')) },
        @{ key = 'scale'; label = 'Escala de resolução'; type = 'combo'; options = @(
                @('50% - bem mais leve', 50), @('75%', 75), @('100% (720p nativo)', 100), @('150% (1080p)', 150), @('200% (1440p)', 200)) },
        @{ key = 'aniso'; label = 'Filtro anisotrópico'; type = 'combo'; options = $AnisoOptions },
        @{ key = 'spuBlock'; label = 'SPU Block Size'; type = 'combo'; options = @(
                @('Safe - mais compatível', 'Safe'), @('Mega - mais FPS', 'Mega'), @('Giga - máximo (pode bugar)', 'Giga')) },
        @{ key = 'frameLimit'; label = 'Limite de FPS'; type = 'combo'; options = @(
                @('Automático', 'Auto'), @('30', '30'), @('60', '60'), @('Sem limite (pode acelerar o jogo)', 'Off')) },
        @{ key = 'stretch'; label = 'Preencher a tela toda (sem bordas pretas)'; type = 'check' },
        @{ key = 'wcb'; label = 'Write Color Buffers (corrige gráficos em alguns jogos)'; type = 'check' },
        @{ key = 'vsync'; label = 'VSync (sem tearing, pode reduzir FPS)'; type = 'check' },
        @{ key = 'showFps'; label = 'Mostrar FPS na tela'; type = 'check' }
    )
    # shadPS4 0.20: gravadas em user\custom_configs\<CUSA>.json (configuração só desse jogo) antes de abrir.
    # Só o que a pessoa sente aparece na tela; o resto (vblank, memória extra, leituras da GPU, cache de shaders,
    # nitidez...) vem da predefinição e das correções conhecidas do jogo ($GameFixes).
    # cond: 'fix' = só em jogo com correção conhecida; 'patch:<key>' = só em jogo que tem esse patch extra
    PS4 = @(
        @{ key = 'anisoInfo'; label = 'Filtro anisotrópico'; type = 'info'; text = 'Definido pelo jogo (o shadPS4 não ajusta)' },
        @{ key = 'present'; label = 'VSync'; type = 'combo'; options = @(
                @('Ligado - sem tearing', 'Fifo'), @('Rápido - pouco atraso (padrão)', 'Mailbox'), @('Desligado - máximo FPS, pode ter tearing', 'Immediate')) },
        @{ key = 'language'; label = 'Idioma do jogo'; type = 'combo'; options = @(
                @('Português (Brasil)', 17), @('Inglês (EUA)', 1), @('Espanhol (América Latina)', 20), @('Espanhol (Espanha)', 3), @('Japonês', 0)) },
        @{ key = 'communityFix'; label = 'Correções da comunidade para este jogo (texturas e shaders sem travar)'; type = 'check'; cond = 'fix' },
        @{ key = 'fps120'; label = '120 FPS'; type = 'check'; cond = 'patch:fps120' },
        @{ key = 'fps60'; label = '60 FPS'; type = 'check'; cond = 'patch:fps60' },
        @{ key = 'fps90'; label = '90 FPS (precisa de PC forte)'; type = 'check'; cond = 'patch:fps90' },
        @{ key = 'officialEmu'; label = 'Testar com o shadPS4 oficial (se o controle tiver atraso)'; type = 'check'; cond = 'patch:officialEmu' },
        @{ key = 'skipVideos'; label = 'Pular vídeos e intros (jogos com patch da comunidade)'; type = 'check' },
        @{ key = 'fsr'; label = 'FSR - imagem mais nítida na tela'; type = 'check' },
        @{ key = 'neo'; label = 'Modo PS4 Pro (jogos com suporte ficam mais bonitos, mais pesado)'; type = 'check' },
        @{ key = 'showFps'; label = 'Mostrar FPS na tela'; type = 'check' }
    )
}

$PresetNames = @('Desempenho máximo (PC fraco)', 'Equilibrado', 'Qualidade (PC forte)')
$Presets = @{
    PS2 = @{
        # fps60: só tem efeito nos jogos com patch de 60 FPS da comunidade (ligado sozinho)
        'Desempenho máximo (PC fraco)' = @{ renderer = 14; scale = 1; eeCycle = -1; mtvu = $true; textures = $true; turbo = 3; fastCdvd = $true; aspect = 'widescreen'; vsync = $false; showFps = $true; fps60 = $true }
        'Equilibrado'                  = @{ renderer = 14; scale = 2; eeCycle = 0; mtvu = $true; textures = $true; turbo = 3; fastCdvd = $false; aspect = 'widescreen'; vsync = $false; showFps = $false; fps60 = $true }
        'Qualidade (PC forte)'         = @{ renderer = 14; scale = 4; eeCycle = 0; mtvu = $true; textures = $true; turbo = 3; fastCdvd = $false; aspect = 'widescreen'; vsync = $true; showFps = $false; fps60 = $true }
    }
    PS3 = @{
        'Desempenho máximo (PC fraco)' = @{ renderer = 'Vulkan'; scale = 75; spuBlock = 'Mega'; frameLimit = 'Auto'; stretch = $true; wcb = $false; vsync = $false; showFps = $true }
        'Equilibrado'                  = @{ renderer = 'Vulkan'; scale = 100; spuBlock = 'Mega'; frameLimit = 'Auto'; stretch = $true; wcb = $false; vsync = $false; showFps = $false }
        'Qualidade (PC forte)'         = @{ renderer = 'Vulkan'; scale = 150; spuBlock = 'Safe'; frameLimit = 'Auto'; stretch = $true; wcb = $false; vsync = $true; showFps = $false }
    }
    PS4 = @{
        'Desempenho máximo (PC fraco)' = @{ skipVideos = $true; screenMode = 'Fullscreen (Borderless)'; present = 'Immediate'; vblank = 60; readbacks = 0; dmem = 0; language = 17; fsr = $false; rcas = $false; neo = $false; pipelineCache = $true; copyBuffers = $false; linearImages = $false; textureFix = $false; fps120 = $false; fps60 = $false; fps90 = $false; eltutz = $false; circleEnter = $false; trophyPopup = $true; showFps = $true }
        'Equilibrado'                  = @{ skipVideos = $true; screenMode = 'Fullscreen (Borderless)'; present = 'Mailbox'; vblank = 60; readbacks = 0; dmem = 0; language = 17; fsr = $true; rcas = $true; neo = $false; pipelineCache = $true; copyBuffers = $false; linearImages = $false; textureFix = $false; fps120 = $false; fps60 = $false; fps90 = $false; eltutz = $false; circleEnter = $false; trophyPopup = $true; showFps = $false }
        'Qualidade (PC forte)'         = @{ skipVideos = $true; screenMode = 'Fullscreen (Borderless)'; present = 'Fifo'; vblank = 60; readbacks = 1; dmem = 0; language = 17; fsr = $true; rcas = $true; neo = $true; pipelineCache = $true; copyBuffers = $false; linearImages = $false; textureFix = $false; fps120 = $false; fps60 = $false; fps90 = $false; eltutz = $false; circleEnter = $false; trophyPopup = $true; showFps = $false }
    }
}

function Get-ConsoleKind($g) {
    if ($g.console -like 'PS3*') { return 'PS3' }
    if ($g.console -like 'PS4*') { return 'PS4' }
    return $g.console
}

# ajustes que a comunidade do shadPS4 confirmou para jogos específicos (valem por cima de qualquer predefinição)
# God of War III Remastered: texturas quebradas/xadrez e personagens escuros sem Readback Linear Images
$GameFixes = @(
    # + patch "Texture Corruption Fix" de cuesta4 (versão 01.02), que precisa de +2 GB de memória
    # + patch de 120 FPS (kvicken) e o shadPS4 eltutz de cuesta4, que compila shaders em segundo plano (como no SpartanPort)
    @{ ids = @('CUSA01623', 'CUSA01715', 'CUSA01720', 'CUSA01740', 'CUSA01741'); values = @{ linearImages = $true; readbacks = 1; pipelineCache = $true; textureFix = $true; dmem = 2048; fps120 = $true; eltutz = $true } },
    # Bloodborne: patches de desempenho do Bloodborne PC ($Ps4PatchSets), 60 FPS e o shadPS4 eltutz
    # (cuesta4 testa com Bloodborne: shaders em segundo plano e ritmo de quadros mais estável).
    # Leituras da GPU em "Relaxado": sem isso aparecem polígonos esticados enormes ("vertex explosion"),
    # é a correção que os desenvolvedores do shadPS4 indicam (custa um pouco de desempenho)
    @{ ids = @('CUSA00207', 'CUSA00208', 'CUSA00299', 'CUSA00900', 'CUSA01363', 'CUSA03014', 'CUSA03023', 'CUSA03173'); values = @{ pipelineCache = $true; eltutz = $true; fps60 = $true; readbacks = 1 } },
    # Shadow of the Colossus: leituras da GPU em "Preciso" (sem isso o menu fica preto e as texturas quebram)
    # e acesso direto à memória ligado, como nas versões do shadPS4 feitas para o SotC (SotC-project, AjncSystem).
    # Sem memória extra: com +2 GB o jogo fecha logo no começo (falta memória de vídeo numa placa de 6 GB).
    @{ ids = @('CUSA08809', 'CUSA08034', 'CUSA08804'); values = @{ readbacks = 2; linearImages = $false; dma = $true; dmem = 0; pipelineCache = $true } }
)

# opções de patch com caixa própria na tela (não seguem "Correções da comunidade")
$OwnPatchOptions = @('fps120', 'fps90', 'fps60')

function Get-GameFix($g) {
    if ((Get-ConsoleKind $g) -ne 'PS4') { return $null }
    foreach ($f in $GameFixes) { foreach ($id in $f.ids) { if ($g.path -match $id -or $g.name -match $id) { return $f.values } } }
    return $null
}

function Get-GameSettings($g) {
    $kind = Get-ConsoleKind $g
    $h = @{ preset = 'Equilibrado' }
    foreach ($k in $CommonDefaults.Keys) { $h[$k] = $CommonDefaults[$k] }
    # base: a predefinição escolhida (as opções que não aparecem na tela vêm dela)
    $pn = 'Equilibrado'
    if ($g.settings -and [string]$g.settings.preset -in $PresetNames) { $pn = [string]$g.settings.preset }
    $p = $Presets[$kind][$pn]
    foreach ($k in $p.Keys) { $h[$k] = $p[$k] }
    $fix = Get-GameFix $g
    if ($fix) { foreach ($k in $fix.Keys) { $h[$k] = $fix[$k] } }
    if ($g.settings) { foreach ($prop in $g.settings.PSObject.Properties) { $h[$prop.Name] = $prop.Value } }
    # "Correções da comunidade" liga ou desliga de uma vez as correções técnicas do jogo (o 120 FPS tem opção própria)
    if ($fix) {
        $on = $true
        if ($g.settings -and $g.settings.PSObject.Properties['communityFix']) { $on = [bool]$g.settings.communityFix }
        $h.communityFix = $on
        foreach ($k in $OwnPatchOptions) { if (-not $g.settings -or -not $g.settings.PSObject.Properties[$k]) { $h[$k] = [bool]$fix[$k] } }
        foreach ($k in $fix.Keys) {
            if ($k -in $OwnPatchOptions) { continue }
            if ($on) { $h[$k] = $fix[$k] } else { $h[$k] = $p[$k] }
        }
    }
    # opções que saíram da tela: seguem as que ficaram
    $h.highPriority = $true
    $h.powerPlan = $true
    $h.rcas = [bool]$h.fsr
    $h.pipelineCache = $true
    return $h
}

# ---------------------------------------------------------------- config do launcher

function Find-EmuExe([string]$key) {
    $dir = Join-Path $EmuRoot $key
    if (-not (Test-Path $dir)) { return $null }
    $f = Get-ChildItem -LiteralPath $dir -Recurse -Filter $EmuInfo[$key].exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

function Update-EmuPaths([bool]$preferBundled) {
    # Os emuladores instalados pelo launcher (pasta emuladores\) têm preferência
    foreach ($k in $EmuKeys) {
        $cur = $script:Cfg[$k]
        $ok = $cur -and (Test-Path -LiteralPath $cur)
        if ($preferBundled -or -not $ok) {
            $found = Find-EmuExe $k
            if ($found) { $script:Cfg[$k] = $found }
        }
    }
}

function Load-Config {
    $cfg = [ordered]@{ pcsx2 = ''; rpcs3 = ''; shadps4 = ''; showSettings = $true; restoreVibrance = $null; viewMode = 'grade'; consoleFilter = 'Todos'; windowBounds = ''; windowMax = $false; showWelcome = $true; sortMode = 'nome'; coverSize = 'medio'; lastUpdateCheck = ''; uiSounds = $true; lang = 'auto'; ps4InstallDir = ''; games = @() }
    if (Test-Path $ConfigPath) {
        try {
            $j = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($EmuKeys) + 'showSettings', 'restoreVibrance', 'viewMode', 'consoleFilter', 'windowBounds', 'windowMax', 'showWelcome', 'sortMode', 'coverSize', 'lastUpdateCheck', 'uiSounds', 'lang', 'ps4InstallDir') {
                if ($null -ne $j.$k) { $cfg[$k] = $j.$k }
            }
            if ($j.games) {
                $cfg.games = @($j.games | ForEach-Object {
                        $o = [pscustomobject]@{ name = $_.name; console = $_.console; path = $_.path; settings = $_.settings; serial = $_.serial }
                        if ($_.running) { $o | Add-Member -NotePropertyName running -NotePropertyValue $true }
                        if ($_.playSeconds) { $o | Add-Member -NotePropertyName playSeconds -NotePropertyValue ([int]$_.playSeconds) }
                        if ($_.lastPlayed) { $o | Add-Member -NotePropertyName lastPlayed -NotePropertyValue ([string]$_.lastPlayed) }
                        if ($_.cover) { $o | Add-Member -NotePropertyName cover -NotePropertyValue ([string]$_.cover) }
                        if ($_.favorite) { $o | Add-Member -NotePropertyName favorite -NotePropertyValue $true }
                        if ($_.added) { $o | Add-Member -NotePropertyName added -NotePropertyValue ([string]$_.added) }
                        if ($_.raGameId) { $o | Add-Member -NotePropertyName raGameId -NotePropertyValue ([int]$_.raGameId) }
                        $o
                    })
            }
        } catch {}
    }
    return $cfg
}

function Save-Config {
    $script:Cfg | ConvertTo-Json -Depth 6 | Set-Content $ConfigPath -Encoding UTF8
}

# ---------------------------------------------------------------- detecção de jogos

function Get-IsoSystemId([string]$path) {
    # Descritor primário ISO9660 em 0x8000; o System Identifier fica em 0x8008.
    # Discos de PS3 usam "PS3VOLUME", discos de PS2 usam "PLAYSTATION".
    try {
        $fs = [IO.File]::OpenRead($path)
        try {
            if ($fs.Length -lt 0x8028) { return '' }
            [void]$fs.Seek(0x8008, 'Begin')
            $b = New-Object byte[] 32
            [void]$fs.Read($b, 0, 32)
            return [Text.Encoding]::ASCII.GetString($b).Trim()
        } finally { $fs.Close() }
    } catch { return '' }
}

function Get-PkgTitleId([string]$path) {
    # Cabeçalho PKG: magic 0x7F 'PKG', Content ID (36 bytes) em 0x30, ex: UP0001-BLUS30443_00-...
    try {
        $fs = [IO.File]::OpenRead($path)
        try {
            $b = New-Object byte[] 0x60
            [void]$fs.Read($b, 0, $b.Length)
            if ($b[0] -ne 0x7F -or $b[1] -ne 0x50 -or $b[2] -ne 0x4B -or $b[3] -ne 0x47) { return $null }
            $cid = [Text.Encoding]::ASCII.GetString($b, 0x30, 36)
            if ($cid -match '^[A-Z]{2}\d{4}-([A-Z]{4}\d{5})') { return $Matches[1] }
        } finally { $fs.Close() }
    } catch {}
    return $null
}

function Get-Ps4PkgTitleId([string]$path) {
    # PKG de PS4: magic 0x7F 'CNT', Content ID (36 bytes) em 0x40, ex: UP9000-CUSA01623_00-...
    try {
        $fs = [IO.File]::OpenRead($path)
        try {
            $b = New-Object byte[] 0x70
            [void]$fs.Read($b, 0, $b.Length)
            if ($b[0] -ne 0x7F -or $b[1] -ne 0x43 -or $b[2] -ne 0x4E -or $b[3] -ne 0x54) { return $null }
            $cid = [Text.Encoding]::ASCII.GetString($b, 0x40, 36)
            if ($cid -match '^[A-Z]{2}\d{4}-([A-Z]{4}\d{5})') { return $Matches[1] }
        } finally { $fs.Close() }
    } catch {}
    return $null
}

function Read-SfoField([string]$sfo, [string]$field) {
    # Lê um campo (TITLE, TITLE_ID...) de um PARAM.SFO do PS3/PS4
    try {
        if (-not (Test-Path -LiteralPath $sfo)) { return $null }
        $b = [IO.File]::ReadAllBytes($sfo)
        if ($b.Length -lt 20 -or $b[1] -ne 0x50) { return $null }
        $keyStart = [BitConverter]::ToUInt32($b, 8)
        $dataStart = [BitConverter]::ToUInt32($b, 12)
        $n = [BitConverter]::ToUInt32($b, 16)
        for ($i = 0; $i -lt $n; $i++) {
            $e = 20 + $i * 16
            $ko = [BitConverter]::ToUInt16($b, $e)
            $len = [BitConverter]::ToUInt32($b, $e + 4)
            $do = [BitConverter]::ToUInt32($b, $e + 12)
            $k = [int]($keyStart + $ko); $end = $k
            while ($b[$end] -ne 0) { $end++ }
            if ([Text.Encoding]::ASCII.GetString($b, $k, $end - $k) -eq $field) {
                return [Text.Encoding]::UTF8.GetString($b, [int]($dataStart + $do), [int]$len).TrimEnd([char]0).Trim()
            }
        }
    } catch {}
    return $null
}

function New-Game($name, $console, $path) {
    [pscustomobject]@{ name = $name; console = $console; path = $path; settings = $null; serial = $null }
}

function Get-Ps4TitleId([string]$dir) {
    $id = Read-SfoField (Join-Path $dir 'sce_sys\param.sfo') 'TITLE_ID'
    if (-not $id -and (Split-Path $dir -Leaf) -match '(CUSA\d{5})') { $id = $Matches[1] }
    return $id
}

function Get-Ps4AppVersion([string]$dir) {
    # versão do jogo (APP_VER); o shadPS4 usa o update da pasta "<jogo>-UPDATE" (ou "-patch") ao lado, se existir
    foreach ($u in "$dir-UPDATE", "$dir-patch") {
        $v = Read-SfoField (Join-Path $u 'sce_sys\param.sfo') 'APP_VER'
        if ($v) { return $v }
    }
    return Read-SfoField (Join-Path $dir 'sce_sys\param.sfo') 'APP_VER'
}

function Get-PatchVersionWarning($g) {
    # patches de jogo valem para uma versão só: avisa quando o jogo está em outra (e como resolver)
    if ((Get-ConsoleKind $g) -ne 'PS4' -or -not (Test-Path -LiteralPath $g.path)) { return '' }
    $tid = Get-Ps4TitleId $g.path
    $ex = @(Get-ExtraPs4Patches $tid)
    $sets = @(Get-Ps4PatchSets $tid)
    if ($ex.Count) { $need = ([xml]$ex[0].xml).Metadata.AppVer }
    elseif ($sets.Count) { $need = $sets[0].appVer }
    else { return '' }
    $have = Get-Ps4AppVersion $g.path
    if (-not $have -or $have -eq $need) { return '' }
    return "Seu jogo está na versão $have e as correções da comunidade são para a ${need}: elas não vão funcionar. Coloque o update $need na pasta ""$(Split-Path $g.path -Leaf)-UPDATE"", ao lado do jogo."
}

function Get-Ps3TitleId($g) {
    if ($g.console -eq 'PS3 (PKG)') { return Get-PkgTitleId $g.path }
    if ($g.path -like '*EBOOT.BIN') {
        $sfo = Join-Path (Split-Path (Split-Path $g.path)) 'PARAM.SFO'
        $id = Read-SfoField $sfo 'TITLE_ID'
        if ($id) { return $id }
    }
    return $null
}

function Get-Ps4Game([string]$dir) {
    # Dump de PS4: pasta com eboot.bin + sce_sys (+ sce_module)
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'eboot.bin')) -or -not (Test-Path -LiteralPath (Join-Path $dir 'sce_sys'))) { return $null }
    $title = Read-SfoField (Join-Path $dir 'sce_sys\param.sfo') 'TITLE'
    if (-not $title) { $title = Split-Path $dir -Leaf }
    $id = Get-Ps4TitleId $dir
    if ($id) { $title = "$title [$id]" }
    return New-Game $title 'PS4' $dir
}

function Detect-Game([string]$path) {
    if (Test-Path -LiteralPath $path -PathType Container) {
        $ps4 = Get-Ps4Game $path
        if ($ps4) { return $ps4 }
        foreach ($rel in 'PS3_GAME\USRDIR\EBOOT.BIN', 'USRDIR\EBOOT.BIN') {
            $eboot = Join-Path $path $rel
            if (Test-Path -LiteralPath $eboot) { return Detect-Game $eboot }
        }
        return $null
    }
    $file = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    if (-not $file) { return $null }
    $ext = $file.Extension.ToLower()
    $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)

    if ($file.Name -ieq 'EBOOT.BIN') {
        $ps4 = Get-Ps4Game $file.Directory.FullName
        if ($ps4) { return $ps4 }
        $gameDir = $file.Directory.Parent   # pasta acima de USRDIR (PS3_GAME ou TITLEID)
        if (-not $gameDir) { return $null }
        $title = Read-SfoField (Join-Path $gameDir.FullName 'PARAM.SFO') 'TITLE'
        if (-not $title) {
            $title = $gameDir.Name
            if ($title -ieq 'PS3_GAME') { $title = $gameDir.Parent.Name }
        }
        return New-Game $title 'PS3' $file.FullName
    }
    switch ($ext) {
        '.pkg' {
            if (Get-PkgTitleId $file.FullName) { return New-Game $name 'PS3 (PKG)' $file.FullName }
            if (Get-Ps4PkgTitleId $file.FullName) { return New-Game $name 'PS4 (PKG)' $file.FullName }
            return $null
        }
        '.iso' {
            if ((Get-IsoSystemId $file.FullName) -match 'PS3') { return New-Game $name 'PS3' $file.FullName }
            return New-Game $name 'PS2' $file.FullName
        }
        { $_ -in '.chd', '.cso', '.zso', '.gz', '.mdf', '.img' } { return New-Game $name 'PS2' $file.FullName }
        '.bin' {
            # .bin pequenos dentro de jogos de PS3 não são imagens de PS2
            if ($file.Length -gt 50MB -and $file.FullName -notmatch '\\USRDIR\\') { return New-Game $name 'PS2' $file.FullName }
        }
    }
    return $null
}

function Find-GamesInFolder([string]$dir) {
    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(iso|chd|cso|zso|gz|bin|mdf|img|pkg)$' })
    # Pastas de PS4 primeiro: os outros arquivos dentro delas não são jogos
    $ps4Dirs = @($files | Where-Object { $_.Name -ieq 'eboot.bin' -and (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'sce_sys')) } |
        ForEach-Object { $_.DirectoryName.ToLower() + '\' })
    foreach ($f in $files) {
        $low = $f.FullName.ToLower()
        $inside = $false
        foreach ($d in $ps4Dirs) { if ($low.StartsWith($d) -and $f.Name -ine 'eboot.bin') { $inside = $true; break } }
        if ($inside) { continue }
        $g = Detect-Game $f.FullName
        if ($g) { $g }
    }
}

function Add-Games([string[]]$paths) {
    $added = 0
    $known = @{}
    foreach ($g in $script:Cfg.games) { $known[$g.path.ToLower()] = $true }
    $list = New-Object System.Collections.ArrayList
    foreach ($p in $paths) {
        $g = Detect-Game $p
        if ($g) { [void]$list.Add($g); continue }
        if (Test-Path -LiteralPath $p -PathType Container) {
            Set-Status "Procurando jogos em $p ..."
            [System.Windows.Forms.Application]::DoEvents()
            foreach ($g in @(Find-GamesInFolder $p)) { [void]$list.Add($g) }
        }
    }
    foreach ($g in $list) {
        if ($known.ContainsKey($g.path.ToLower())) { continue }
        $known[$g.path.ToLower()] = $true
        $g | Add-Member -NotePropertyName added -NotePropertyValue ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -Force   # para "Adicionados por último"
        $script:Cfg.games = @($script:Cfg.games) + $g
        $added++
    }
    Save-Config
    # o último jogo adicionado já fica escolhido (painel mostra ele)
    $last = $null
    foreach ($g in $list) { $last = $g }
    if ($added -gt 0 -and $last) { foreach ($it in $lv.SelectedItems) { $it.Selected = $false } }
    Refresh-List
    if ($added -gt 0 -and $last) { Select-Game $last }
    Set-Status "$added jogo(s) adicionado(s)."
    if ($added -eq 1) { Show-Toast "Jogo adicionado: $($last.name)" 'ok' }
    elseif ($added -gt 1) { Show-Toast "$added jogos adicionados" 'ok' }
    elseif ($list.Count -gt 0) { Show-Toast 'Esses jogos já estão na biblioteca' 'info' }
    else { Show-Toast 'Nenhum jogo reconhecido nesses arquivos' 'warn' }
}

# ---------------------------------------------------------------- aplicar configurações nos emuladores


function Set-IniValues([string]$path, $values, [string]$sep = ' = ') {
    # $values: @{ 'Secao' = @{ chave = valor } } - altera só essas chaves, mantém o resto do arquivo
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $path) {
        $c = @(Get-Content -LiteralPath $path -Encoding UTF8)
        if ($c.Count) { $lines.AddRange([string[]]$c) }
    }
    foreach ($sec in $values.Keys) {
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq "[$sec]") { $start = $i; break } }
        if ($start -lt 0) {
            if ($lines.Count -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
            $lines.Add("[$sec]"); $start = $lines.Count - 1
        }
        $end = $lines.Count
        for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end = $i; break } }
        foreach ($k in $values[$sec].Keys) {
            $v = $values[$sec][$k]
            if ($v -is [bool]) { $v = $v.ToString().ToLower() }
            $found = $false
            for ($i = $start + 1; $i -lt $end; $i++) {
                if ($lines[$i] -match "^\s*$([regex]::Escape($k))\s*=") { $lines[$i] = "$k$sep$v"; $found = $true; break }
            }
            if (-not $found) {
                $insert = $end
                while ($insert -gt $start + 1 -and -not $lines[$insert - 1].Trim()) { $insert-- }
                $lines.Insert($insert, "$k$sep$v"); $end++
            }
        }
    }
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Get-Ps2Serial([string]$path) {
    # Lê o SYSTEM.CNF da ISO (ISO9660) e tira o código do jogo do BOOT2, ex: cdrom0:\SCUS_974.81;1 -> SCUS-97481
    if ($path -notmatch '(?i)\.iso$') { return $null }
    try {
        $fs = [IO.File]::OpenRead($path)
        try {
            $pvd = New-Object byte[] 2048
            [void]$fs.Seek(16 * 2048, 'Begin'); [void]$fs.Read($pvd, 0, 2048)
            $rootLba = [BitConverter]::ToUInt32($pvd, 158); $rootLen = [int][BitConverter]::ToUInt32($pvd, 166)
            if ($rootLen -le 0 -or $rootLen -gt 1MB) { return $null }
            $dir = New-Object byte[] $rootLen
            [void]$fs.Seek([int64]$rootLba * 2048, 'Begin'); [void]$fs.Read($dir, 0, $rootLen)
            $i = 0
            while ($i -lt $rootLen - 33) {
                $len = $dir[$i]
                if ($len -eq 0) { $i = ([math]::Floor($i / 2048) + 1) * 2048; continue }   # registros não cruzam setores
                $name = [Text.Encoding]::ASCII.GetString($dir, $i + 33, $dir[$i + 32])
                if ($name -like 'SYSTEM.CNF*') {
                    $lba = [BitConverter]::ToUInt32($dir, $i + 2)
                    $buf = New-Object byte[] ([math]::Min([BitConverter]::ToUInt32($dir, $i + 10), 4096))
                    [void]$fs.Seek([int64]$lba * 2048, 'Begin'); [void]$fs.Read($buf, 0, $buf.Length)
                    if ([Text.Encoding]::ASCII.GetString($buf) -match 'BOOT2?\s*=\s*cdrom0?:\\?([A-Z]{4})_(\d{3})\.(\d{2})') {
                        return "$($Matches[1])-$($Matches[2])$($Matches[3])"
                    }
                    return $null
                }
                $i += $len
            }
        } finally { $fs.Close() }
    } catch {}
    return $null
}

function Get-Ps2NameKey([string]$name) {
    # "Midnight Club 3 - DUB Edition Remix (USA)" -> "midnightclub3dubeditionremix"
    return (($name -replace '\s*[\(\[].*$', '').ToLower() -replace '[^a-z0-9]', '')
}

function Get-Ps2SerialByName([string]$name) {
    # CHD, CSO e parecidos são comprimidos: sem ler o disco, procura o nome na lista do PCSX2 (só nome exato, para não errar de jogo)
    if ($null -eq $script:Ps2NameIndex) {
        $script:Ps2NameIndex = @{}
        if (-not $script:Cfg.pcsx2) { return $null }
        $f = Join-Path (Split-Path $script:Cfg.pcsx2) 'resources\GameIndex.yaml'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f), '(?m)^([A-Z]{4}-\d{5}):\s*\r?\n\s+name:\s*"?([^"\r\n]+?)"?\s*\r?\n(?:\s+name-\S+:.*\r?\n)*\s+region:\s*"?([^"\r\n]+)')) {
            $k = Get-Ps2NameKey $m.Groups[2].Value
            if (-not $k) { continue }
            if (-not $script:Ps2NameIndex.ContainsKey($k)) { $script:Ps2NameIndex[$k] = @() }
            $script:Ps2NameIndex[$k] += , @($m.Groups[1].Value, $m.Groups[3].Value)
        }
    }
    $list = $script:Ps2NameIndex[(Get-Ps2NameKey $name)]
    if (-not $list) { return $null }
    $want = switch -Regex ($name) {
        '\((Europe|Germany|France|Spain|Italy|UK|Australia|E)\b' { 'PAL'; break }
        '\((Japan|J)\b' { 'NTSC-J'; break }
        '\((Korea|K)\b' { 'NTSC-K'; break }
        default { 'NTSC-U' }
    }
    foreach ($e in $list) { if ($e[1] -match "^$want(-|$)") { return $e[0] } }   # NTSC-U e não NTSC-Unk
    return $list[0][0]
}

function Get-GameSerial($g) {
    if ($g.serial) { return $g.serial }
    $s = Get-Ps2Serial $g.path
    if (-not $s) { $s = Get-Ps2SerialByName $g.name }
    if (-not $s -and $g.path) { $s = Get-Ps2SerialByName ([IO.Path]::GetFileNameWithoutExtension($g.path)) }
    return $s
}

# ---------------------------------------------------------------- patches de FPS do PS2
# O PCSX2 traz em resources\patches.zip os patches da comunidade (PCSX2/pcsx2_patches), um arquivo por jogo:
# <SERIAL>_<CRC>.pnach. Os que têm uma seção "60 FPS" (ou "50/60 FPS", "50 FPS" nos jogos PAL) são ligados
# sozinhos pelo launcher, em gamesettings\<SERIAL>_<CRC>.ini ([Patches] Enable = nome), a mesma
# configuração por jogo que a tela do PCSX2 grava.
# O CRC é o que o PCSX2 usa: XOR de todas as palavras de 32 bits do executável do jogo (o ELF do BOOT2).
Add-Type -Namespace PL -Name Ps2Crc -MemberDefinition @'
public static uint Of(byte[] d) { uint c = 0; for (int i = 0; i + 3 < d.Length; i += 4) c ^= System.BitConverter.ToUInt32(d, i); return c; }
'@
$script:Ps2CrcCache = @{}
$Ps2FpsPatchName = '(?i)^(force )?(ntsc mode/)?((50/)?60|50) ?fps( hack)?$'

function Get-Ps2Crc($g, [string]$exe) {
    if ($script:Ps2CrcCache.ContainsKey($g.path)) { return $script:Ps2CrcCache[$g.path] }
    $crc = $null
    if ($g.path -match '(?i)\.iso$') {
        $cnf = Read-IsoFile $g.path 'SYSTEM.CNF' 64KB
        if ($cnf -and [Text.Encoding]::ASCII.GetString($cnf) -match '(?i)BOOT2\s*=\s*cdrom0?:\\?([^;\r\n]+)') {
            $elf = Read-IsoFile $g.path ($Matches[1].Trim().Replace('\', '/')) 32MB
            if ($elf) { $crc = '{0:X8}' -f [PL.Ps2Crc]::Of($elf) }
        }
    }
    if (-not $crc -and $exe) {
        # CHD/CSO/BIN: o PCSX2 põe o CRC no nome dos saves de estado ("SLUS-21029 (4A0E5B3A).1.p2s")
        $serial = Get-GameSerial $g
        $st = Join-Path (Get-Pcsx2DataDir $exe) 'sstates'
        if ($serial -and (Test-Path -LiteralPath $st)) {
            $f = Get-ChildItem -LiteralPath $st -File -Filter "$serial (*).p2s*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f -and $f.Name -match '\(([0-9A-F]{8})\)') { $crc = $Matches[1] }
        }
    }
    if ($crc) { $script:Ps2CrcCache[$g.path] = $crc }
    return $crc
}

function Get-Ps2FpsPatch($g, [string]$exe) {
    # devolve @{ id = 'SERIAL_CRC'; name = '60 FPS'; names = (todas as seções de FPS); ee = overclock pedido } ou $null
    if ((Get-ConsoleKind $g) -ne 'PS2') { return $null }
    if (-not $exe) { $exe = $script:Cfg.pcsx2 }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $null }
    $serial = Get-GameSerial $g
    $crc = Get-Ps2Crc $g $exe
    if (-not $serial -or -not $crc) { return $null }
    $id = "${serial}_$crc"
    $texts = @()
    # patch que a pessoa colocou na pasta patches do PCSX2 vale junto com os do pacote
    foreach ($n in "$id.pnach", "$crc.pnach") {
        $f = Join-Path (Join-Path (Get-Pcsx2DataDir $exe) 'patches') $n
        if (Test-Path -LiteralPath $f) { $texts += [IO.File]::ReadAllText($f) }
    }
    $zipPath = Join-Path (Split-Path $exe) 'resources\patches.zip'
    if (Test-Path -LiteralPath $zipPath) {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $e = $z.GetEntry("$id.pnach")
            if ($e) { $r = New-Object IO.StreamReader($e.Open()); $texts += $r.ReadToEnd(); $r.Close() }
        } finally { $z.Dispose() }
    }
    $found = @()
    foreach ($t in $texts) {
        $cur = $null
        foreach ($line in $t -split "`r?`n") {
            if ($line -match '^\s*\[(.+)\]\s*$') { $cur = $null; if ($Matches[1].Trim() -match $Ps2FpsPatchName) { $cur = @{ name = $Matches[0]; desc = '' }; $found += $cur } }
            elseif ($cur -and $line -match '^\s*description\s*=(.*)') { $cur.desc = $Matches[1].Trim() }
        }
    }
    if (-not $found) { return $null }
    # o de 60 tem preferência (jogos PAL às vezes têm 50 e 60)
    $best = @($found | Sort-Object { if ($_.name -match '60') { 0 } else { 1 } })[0]
    # "Might need EE Overclock (180%)", "Requires 300% EE Overclock": a CPU do PS2 precisa ir mais rápido
    $ee = 0
    if ($best.desc -match '300\s*%') { $ee = 3 } elseif ($best.desc -match '180\s*%') { $ee = 2 } elseif ($best.desc -match '130\s*%') { $ee = 1 }
    return @{ id = $id; name = $best.name; names = @($found | ForEach-Object { $_.name }); ee = $ee }
}

function Set-Ps2FpsPatch([string]$exe, $fp, [bool]$on) {
    # liga/desliga só a linha do patch de FPS em [Patches]; o resto do arquivo do jogo fica como está
    $ini = Join-Path (Get-Pcsx2DataDir $exe) "gamesettings\$($fp.id).ini"
    $lines = New-Object Collections.Generic.List[string]
    if (Test-Path -LiteralPath $ini) { $lines.AddRange([string[]](Get-Content -LiteralPath $ini -Encoding UTF8)) }
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq '[Patches]') { $start = $i; break } }
    if ($start -lt 0) {
        if (-not $on) { return }
        if ($lines.Count -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
        $lines.Add('[Patches]'); $start = $lines.Count - 1
    }
    $end = $start + 1
    while ($end -lt $lines.Count -and $lines[$end].Trim() -notmatch '^\[') { $end++ }
    for ($i = $end - 1; $i -gt $start; $i--) {
        if ($lines[$i] -match '^\s*Enable\s*=\s*(.+?)\s*$' -and $Matches[1] -in $fp.names) { $lines.RemoveAt($i); $end-- }
    }
    if ($on) { $lines.Insert($start + 1, "Enable = $($fp.name)") }
    New-Item -ItemType Directory -Force (Split-Path $ini) | Out-Null
    [IO.File]::WriteAllLines($ini, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Read-IsoFile([string]$iso, [string]$filePath, [int]$maxBytes = 4MB) {
    # lê um arquivo de dentro de uma ISO (ISO9660) pelo caminho, ex: PS3_GAME/ICON0.PNG
    try {
        $fs = [IO.File]::OpenRead($iso)
        try {
            $pvd = New-Object byte[] 2048
            [void]$fs.Seek(16 * 2048, 'Begin'); [void]$fs.Read($pvd, 0, 2048)
            $lba = [BitConverter]::ToUInt32($pvd, 158); $size = [int][BitConverter]::ToUInt32($pvd, 166)
            $parts = $filePath.Split('/')
            for ($p = 0; $p -lt $parts.Count; $p++) {
                if ($size -le 0 -or $size -gt 4MB) { return $null }
                $dir = New-Object byte[] $size
                [void]$fs.Seek([int64]$lba * 2048, 'Begin'); [void]$fs.Read($dir, 0, $size)
                $found = $false; $i = 0
                while ($i -lt $size - 33) {
                    $len = $dir[$i]
                    if ($len -eq 0) { $i = ([math]::Floor($i / 2048) + 1) * 2048; continue }
                    $name = ([Text.Encoding]::ASCII.GetString($dir, $i + 33, $dir[$i + 32]) -split ';')[0]
                    if ($name -ieq $parts[$p]) {
                        $lba = [BitConverter]::ToUInt32($dir, $i + 2); $size = [int][BitConverter]::ToUInt32($dir, $i + 10)
                        $found = $true; break
                    }
                    $i += $len
                }
                if (-not $found) { return $null }
            }
            if ($size -gt $maxBytes) { return $null }
            $buf = New-Object byte[] $size
            [void]$fs.Seek([int64]$lba * 2048, 'Begin'); [void]$fs.Read($buf, 0, $size)
            return , $buf
        } finally { $fs.Close() }
    } catch { return $null }
}

# ---------------------------------------------------------------- capas dos jogos
# PS2: capa do repositório xlenore/ps2-covers (o mesmo usado com o PCSX2), pelo código do disco.
# PS3/PS4: o ícone que vem no próprio jogo (ICON0.PNG / sce_sys\icon0.png). Guardadas em app\covers.
$CoverDir = Join-Path $Root 'covers'
$CoverW = 48; $CoverH = 64      # modo lista
$GridW = 150; $GridH = 200      # modo grade (capa grande)

function Get-CoverKey($g) {
    $id = $null
    switch -Wildcard ($g.console) {
        'PS2' { $id = Get-GameSerial $g }
        'PS3*' { $id = Get-Ps3TitleId $g }
        'PS4 (PKG)' { $id = Get-Ps4PkgTitleId $g.path }
        'PS4' { $id = Get-Ps4TitleId $g.path }
    }
    if (-not $id) {
        $md5 = [Security.Cryptography.MD5]::Create()
        $id = -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($g.path.ToLower()))[0..7] | ForEach-Object { $_.ToString('x2') })
    }
    return ($g.console -replace '[^A-Za-z0-9]', '') + '_' + $id
}

function Get-LocalCoverBytes($g) {
    # imagem que o próprio jogo traz (PS3/PS4)
    try {
        if ($g.console -eq 'PS4') {
            $f = Join-Path $g.path 'sce_sys\icon0.png'
            if (Test-Path -LiteralPath $f) { return , [IO.File]::ReadAllBytes($f) }
        } elseif ($g.console -eq 'PS3' -and $g.path -like '*EBOOT.BIN') {
            $f = Join-Path (Split-Path (Split-Path $g.path)) 'ICON0.PNG'
            if (Test-Path -LiteralPath $f) { return , [IO.File]::ReadAllBytes($f) }
        } elseif ($g.console -eq 'PS3' -and $g.path -match '(?i)\.iso$') {
            return (Read-IsoFile $g.path 'PS3_GAME/ICON0.PNG')
        } elseif ($g.console -eq 'PS3 (PKG)' -and $script:Cfg.rpcs3) {
            $f = Join-Path (Split-Path $script:Cfg.rpcs3) "dev_hdd0\game\$(Get-PkgTitleId $g.path)\ICON0.PNG"
            if (Test-Path -LiteralPath $f) { return , [IO.File]::ReadAllBytes($f) }
        }
    } catch {}
    return $null
}

function New-CoverTile([System.Drawing.Image]$img, [string]$console, [int]$W = $CoverW, [int]$H = $CoverH) {
    # encaixa a imagem (capa em pé ou ícone quadrado) no quadro, sem distorcer.
    # No quadro grande: capa preenchendo o quadro (corta as sobras) e etiqueta do console no canto.
    $big = $W -ge 100
    $tile = New-Object System.Drawing.Bitmap($W, $H)
    $gr = [System.Drawing.Graphics]::FromImage($tile)
    $gr.InterpolationMode = 'HighQualityBicubic'; $gr.SmoothingMode = 'AntiAlias'; $gr.PixelOffsetMode = 'HighQuality'
    $gr.TextRenderingHint = 'AntiAliasGridFit'
    $gr.Clear([System.Drawing.Color]::FromArgb(24, 24, 28))
    $c = [System.Drawing.Color]::FromArgb(110, 110, 125)
    if ($console -and $consoleColors.ContainsKey($console)) { $c = $consoleColors[$console] }
    $pad = if ($big) { 0 } else { 2 }
    if ($img) {
        $portrait = $img.Height -gt $img.Width * 1.1
        if ($big -and $portrait) { $r = [math]::Max($W / $img.Width, $H / $img.Height) }   # capa em pé: preenche
        else { $r = [math]::Min(($W - 2 * $pad) / $img.Width, ($H - 2 * $pad) / $img.Height) }
        # (PowerShell não diferencia maiúsculas: $dw/$dh para não sobrescrever $W/$H)
        $dw = [int]($img.Width * $r); $dh = [int]($img.Height * $r)
        if ($big -and -not $portrait) {
            # ícone quadrado (PS3/PS4): fundo com o próprio ícone esticado e escuro, ícone inteiro no meio
            $rb = [math]::Max($W / $img.Width, $H / $img.Height)
            $bw = [int]($img.Width * $rb); $bh = [int]($img.Height * $rb)
            $gr.DrawImage($img, [int](($W - $bw) / 2), [int](($H - $bh) / 2), $bw, $bh)
            $gr.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, 16, 16, 20))), 0, 0, $W, $H)
        }
        $gr.DrawImage($img, [int](($W - $dw) / 2), [int](($H - $dh) / 2), $dw, $dh)
    } else {
        $gr.DrawRectangle((New-Object System.Drawing.Pen($c, 1.5)), 3, 3, $W - 7, $H - 7)
        $fs = if ($big) { 20 } else { 9 }
        $f = New-Object System.Drawing.Font('Segoe UI', $fs, [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $gr.DrawString((L (($console -replace ' \(PKG\)', ''))), $f, (New-Object System.Drawing.SolidBrush($c)), (New-Object System.Drawing.RectangleF(0, 0, $W, $H)), $sf)
    }
    if ($big -and $img -and $console) {
        # etiqueta do console no canto de baixo
        $label = $console -replace ' \(PKG\)', ' PKG'
        $f = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
        $sz = $gr.MeasureString($label, $f)
        $bx = $W - $sz.Width - 10; $by = $H - $sz.Height - 8
        $gr.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 16, 16, 20))), $bx - 4, $by - 1, $sz.Width + 8, $sz.Height + 2)
        $gr.DrawString((L ($label)), $f, (New-Object System.Drawing.SolidBrush($c)), $bx, $by)
    }
    $gr.DrawRectangle((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 60, 70), 1)), 0, 0, $W - 1, $H - 1)
    $gr.Dispose()
    return $tile
}

function New-CoverPlaceholder([string]$console, [int]$W = $CoverW, [int]$H = $CoverH) {
    return (New-CoverTile $null $console $W $H)
}

function Save-CoverFile([byte[]]$bytes, [string]$file) {
    # guarda a capa já reduzida (fica leve e abre rápido)
    try {
        $ms = New-Object IO.MemoryStream(, $bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        $r = [math]::Min(1.0, [math]::Min(($GridW * 2) / $img.Width, ($GridH * 2) / $img.Height))
        $bmp = New-Object System.Drawing.Bitmap($img, [int]($img.Width * $r), [int]($img.Height * $r))
        $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose(); $img.Dispose(); $ms.Dispose()
        return $true
    } catch { return $false }
}

function Get-Pcsx2TextureDir([string]$exe, [string]$serial) {
    # o PCSX2 procura as texturas em textures\<código>\replacements
    return Join-Path (Get-Pcsx2DataDir $exe) "textures\$serial\replacements"
}

function Find-7z {
    foreach ($p in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Install-TexturePack([string]$exe, [string]$serial, [string]$source) {
    # Aceita pasta ou arquivo (.zip; .7z/.rar com o 7-Zip instalado). Retorna o total de arquivos de textura do jogo.
    $dest = Get-Pcsx2TextureDir $exe $serial
    $tmp = $null; $root = $source
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        $tmp = Join-Path $env:TEMP ('TriviumHub-tex-' + [guid]::NewGuid())
        New-Item -ItemType Directory $tmp | Out-Null
        if ($source -match '(?i)\.zip$') { & tar.exe -xf $source -C $tmp }
        else {
            $7z = Find-7z
            if (-not $7z) { Remove-Item -Recurse -Force $tmp; throw 'Para .7z e .rar é preciso ter o 7-Zip instalado (ou extraia o pacote e use "Instalar de pasta").' }
            & $7z x -y "-o$tmp" $source | Out-Null
        }
        $root = $tmp
    }
    try {
        # o conteúdo útil é a pasta "replacements" do pacote; sem ela, usa a raiz (ou a única pasta dentro)
        $rep = Get-ChildItem -LiteralPath $root -Directory -Recurse -Filter 'replacements' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($rep) { $src = $rep.FullName }
        else {
            $items = @(Get-ChildItem -LiteralPath $root)
            if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $src = $items[0].FullName } else { $src = $root }
        }
        New-Item -ItemType Directory -Force $dest | Out-Null
        foreach ($it in Get-ChildItem -LiteralPath $src) { Copy-Item -LiteralPath $it.FullName -Destination $dest -Recurse -Force }
    } finally {
        if ($tmp) { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    }
    return @(Get-ChildItem -LiteralPath $dest -Recurse -File).Count
}

function Update-IniSection([string]$path, [string]$section, [scriptblock]$keep, [string[]]$add) {
    # Reescreve uma seção mantendo só as linhas aprovadas por $keep e acrescentando $add.
    # Necessário para as ligações de controle do PCSX2, que usam a mesma chave em várias linhas.
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $path) {
        $c = @(Get-Content -LiteralPath $path -Encoding UTF8)
        if ($c.Count) { $lines.AddRange([string[]]$c) }
    }
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq "[$section]") { $start = $i; break } }
    if ($start -lt 0) {
        if ($lines.Count -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
        $lines.Add("[$section]"); $start = $lines.Count - 1
    }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith('[')) { $end = $i; break } }
    $body = @($lines.GetRange($start + 1, $end - $start - 1) | Where-Object { $_.Trim() -and (& $keep $_) }) + $add + @('', '')
    $lines.RemoveRange($start + 1, $end - $start - 1)
    $lines.InsertRange($start + 1, [string[]]$body)
    [IO.File]::WriteAllLines($path, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Get-Pcsx2PadLines([int]$index) {
    # Ligações no padrão de controle do SDL: funciona com Xbox, PlayStation, Switch e controles genéricos conhecidos
    $map = [ordered]@{
        Up = 'DPadUp'; Right = 'DPadRight'; Down = 'DPadDown'; Left = 'DPadLeft'
        Triangle = 'FaceNorth'; Circle = 'FaceEast'; Cross = 'FaceSouth'; Square = 'FaceWest'; Select = 'Back'; Start = 'Start'
        L1 = 'LeftShoulder'; R1 = 'RightShoulder'; L2 = '+LeftTrigger'; R2 = '+RightTrigger'; L3 = 'LeftStick'; R3 = 'RightStick'
        LUp = '-LeftY'; LRight = '+LeftX'; LDown = '+LeftY'; LLeft = '-LeftX'
        RUp = '-RightY'; RRight = '+RightX'; RDown = '+RightY'; RLeft = '-RightX'
        LargeMotor = 'LargeMotor'; SmallMotor = 'SmallMotor'
    }
    foreach ($k in $map.Keys) { "$k = SDL-$index/$($map[$k])" }
}

function Set-Pcsx2Controllers([string]$ini) {
    # Jogador 1: teclado + 1º controle; jogador 2: 2º controle. Select+Start abre o menu (dá para sair do jogo pelo controle).
    Set-IniValues $ini ([ordered]@{ 'InputSources' = [ordered]@{ SDL = $true; SDLControllerEnhancedMode = $true; XInput = $false; DInput = $false } })
    Update-IniSection $ini 'Pad1' { param($l) $l -notmatch 'SDL-' } (Get-Pcsx2PadLines 0)
    Update-IniSection $ini 'Pad2' { param($l) $l -notmatch 'SDL-' -and $l -notmatch '^\s*Type\s*=' } (@('Type = DualShock2') + (Get-Pcsx2PadLines 1))
    # segurar o botão PS/Xbox (ou o touchpad do DualShock 4/DualSense) acelera o jogo: passa cutscenes rápido
    Update-IniSection $ini 'Hotkeys' { param($l) $l -notmatch 'SDL-' } @(
        'OpenPauseMenu = SDL-0/Back & SDL-0/Start', 'HoldTurbo = SDL-0/Guide', 'HoldTurbo = SDL-0/Touchpad')
}

function Get-ConnectedPadKind {
    # Controles da Sony têm handler próprio no RPCS3; Xbox e compatíveis usam XInput (interface "IG_")
    $ids = @(Get-PnpDevice -PresentOnly -Class HIDClass -ErrorAction SilentlyContinue | ForEach-Object InstanceId)
    if ($ids -match '(?i)VID[_&](0002)?054C[_&]PID[_&](0CE6|0DF2)') { return 'DualSense' }
    if ($ids -match '(?i)VID[_&](0002)?054C[_&]PID[_&](05C4|09CC|0BA0)') { return 'DualShock 4' }
    if ($ids -match '(?i)VID[_&](0002)?054C[_&]PID[_&]0268') { return 'DualShock 3' }
    if ($ids -match '(?i)IG_\d') { return 'XInput' }
    return 'Keyboard'
}

function Set-Rpcs3Controller([string]$exe) {
    # O RPCS3 usa um tipo de controle por jogador: escolhe o que estiver conectado (sem controle = teclado).
    # Sem a seção Config, o RPCS3 usa o mapeamento padrão daquele tipo de controle.
    $kind = Get-ConnectedPadKind
    $device = switch ($kind) {
        'DualSense' { 'DualSense Pad #1' } 'DualShock 4' { 'DS4 Pad #1' } 'DualShock 3' { 'DS3 Pad #1' }
        'XInput' { 'XInput Pad #1' } default { 'Keyboard' }
    }
    $dir = Join-Path (Split-Path $exe) 'config\input_configs\global'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $yaml = "Player 1 Input:`n  Handler: $kind`n  Device: $device`n"
    [IO.File]::WriteAllText((Join-Path $dir 'Default.yml'), $yaml, (New-Object Text.UTF8Encoding($false)))
    return $kind
}

function Get-Pcsx2DataDir([string]$exe) {
    $d = Split-Path $exe
    if ((Test-Path (Join-Path $d 'portable.ini')) -or (Test-Path (Join-Path $d 'portable.txt'))) { return $d }
    return Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PCSX2'
}

function Get-Pcsx2Ini([string]$exe) {
    return Join-Path (Get-Pcsx2DataDir $exe) 'inis\PCSX2.ini'
}

function Get-Ps2BiosInfo([string]$file) {
    # BIOS do PS2: ~4 MB, com a tabela ROMDIR (RESET, ROMDIR, ROMVER...).
    # ROMVER = versão (4 dígitos) + região + tipo + data, ex: 0160AC20020207
    try {
        $fi = Get-Item -LiteralPath $file
        if ($fi.Length -lt 4MB -or $fi.Length -gt 32MB) { return $null }
        $fs = [IO.File]::OpenRead($file)
        try { $b = New-Object byte[] 0x80000; $n = $fs.Read($b, 0, $b.Length) } finally { $fs.Close() }
        $t = [Text.Encoding]::ASCII.GetString($b, 0, $n)
        if (-not ($t.Contains('RESET') -and $t.Contains('ROMDIR'))) { return $null }
        $info = @{ version = '?'; region = '?' }
        if ($t -cmatch '(\d{2})(\d{2})([JAEHCT])[CDTX](\d{4})(\d{2})(\d{2})') {
            $info.version = "$([int]$Matches[1]).$($Matches[2])"
            $info.region = @{ J = 'Japão'; A = 'EUA'; E = 'Europa'; H = 'Ásia'; C = 'China'; T = 'T10K' }[$Matches[3]]
        }
        return $info
    } catch { return $null }
}

function Test-Pcsx2Ready([string]$exe) {
    # pronto = assistente do PCSX2 dispensado e BIOS escolhida existindo na pasta bios
    $ini = Get-Pcsx2Ini $exe
    if (-not (Test-Path -LiteralPath $ini)) { return $false }
    $txt = Get-Content -LiteralPath $ini -Raw
    if ($txt -match '(?m)^\s*SetupWizardIncomplete\s*=\s*true') { return $false }
    if ($txt -cnotmatch '(?m)^\s*BIOS\s*=[ \t]*(\S[^\r\n]*)') { return $false }
    return Test-Path -LiteralPath (Join-Path (Join-Path (Get-Pcsx2DataDir $exe) 'bios') $Matches[1].Trim())
}

function Get-Pcsx2BiosDir([string]$exe) {
    return Join-Path (Get-Pcsx2DataDir $exe) 'bios'
}

function Get-InstalledPs2Bioses([string]$exe) {
    # BIOS válidas na pasta bios do PCSX2, da mais nova para a mais antiga
    $dir = Get-Pcsx2BiosDir $exe
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $list = foreach ($f in Get-ChildItem -LiteralPath $dir -File) {
        if ($f.Extension -in '.mec', '.nvm', '.rom1', '.rom2', '.erom') { continue }
        $i = Get-Ps2BiosInfo $f.FullName
        if ($i) { [pscustomobject]@{ name = $f.Name; version = $i.version; region = $i.region; label = "$($i.region)  v$($i.version)  -  $($f.Name)" } }
    }
    return @($list | Sort-Object @{ e = { [double]($_.version -replace '\?', '0') }; Descending = $true }, region, name)
}

function Import-Ps2Bioses([string]$exe, [string[]]$files) {
    # Copia as BIOS válidas (e os .mec/.nvm de mesmo nome) para dentro do app, sem repetir arquivos iguais.
    # Retorna quantas BIOS novas entraram.
    $dir = Get-Pcsx2BiosDir $exe
    New-Item -ItemType Directory -Force $dir | Out-Null
    $known = @{}
    foreach ($b in Get-InstalledPs2Bioses $exe) { $known[(Get-FileHash -LiteralPath (Join-Path $dir $b.name) -Algorithm MD5).Hash] = $true }
    $added = 0
    foreach ($file in $files) {
        if (-not (Get-Ps2BiosInfo $file)) { continue }
        $hash = (Get-FileHash -LiteralPath $file -Algorithm MD5).Hash
        if ($known.ContainsKey($hash)) { continue }
        $known[$hash] = $true
        $base = [IO.Path]::GetFileNameWithoutExtension($file)
        Get-ChildItem -LiteralPath (Split-Path $file) -File | Where-Object { $_.BaseName -eq $base } | ForEach-Object {
            try { Copy-Item -LiteralPath $_.FullName -Destination $dir -Force -ErrorAction Stop } catch {}
        }
        $added++
    }
    return $added
}

function Select-Pcsx2Bios([string]$exe, [string]$name) {
    # escolhe a BIOS e dispensa o assistente do PCSX2, deixando ele com cara de parte do launcher
    Set-IniValues (Get-Pcsx2Ini $exe) ([ordered]@{
            # SettingsVersion: sem ela o PCSX2 acha o arquivo inválido e pergunta se quer apagar tudo
            # (acontece na instalação nova, quando o launcher cria o PCSX2.ini antes do PCSX2 abrir)
            'UI'          = [ordered]@{ SettingsVersion = 1; SetupWizardIncomplete = $false; ConfirmShutdown = $false; PauseOnFocusLoss = $false; HideMouseCursor = $true }
            'Folders'     = [ordered]@{ Bios = 'bios' }
            'Filenames'   = [ordered]@{ BIOS = $name }
            'AutoUpdater' = [ordered]@{ CheckAtStartup = $false }
        })
}

function Select-DefaultPs2Bios([string]$exe) {
    # sem BIOS escolhida: usa a mais nova dos EUA (roda jogos de qualquer região no PCSX2)
    if (Test-Pcsx2Ready $exe) { return }
    $all = Get-InstalledPs2Bioses $exe
    if (-not $all.Count) { return }
    $best = $all | Where-Object { $_.region -eq 'EUA' } | Select-Object -First 1
    if (-not $best) { $best = $all[0] }
    Select-Pcsx2Bios $exe $best.name
}

# ---------------------------------------------------------------- save automático (PS2)
# O launcher pede ao PCSX2, pelo PINE (TCP local), para salvar o estado no slot 10 de tempos em tempos.
# Se o jogo fechar com erro (ou o PC desligar), na próxima vez o launcher oferece continuar desse save.
$PineSlot = 28011
$AutoSaveSlot = 10

function Invoke-Pine([byte[]]$cmd) {
    # mensagem PINE: tamanho total (uint32) + comando; resposta: tamanho (uint32) + resultado (0 = ok) + dados
    $c = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect('127.0.0.1', $PineSlot, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne(1000)) { return $null }
        $c.EndConnect($ar)
        $c.ReceiveTimeout = 5000
        $st = $c.GetStream()
        $msg = [byte[]]([BitConverter]::GetBytes([uint32](4 + $cmd.Length)) + $cmd)
        $st.Write($msg, 0, $msg.Length)
        $buf = New-Object byte[] 64; $n = 0
        while ($n -lt 5) { $r = $st.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r }
        if ($n -lt 5) { return $null }
        return $buf[0..($n - 1)]
    } catch { return $null } finally { $c.Close() }
}

function Save-Pcsx2AutoState {
    # só salva com o jogo rodando (status 0); em pausa, menu ou modo Hardcore o PCSX2 recusa
    $st = Invoke-Pine ([byte[]]@(0x0F))
    if (-not $st -or $st[4] -ne 0 -or $st.Count -lt 9 -or [BitConverter]::ToUInt32([byte[]]$st, 5) -ne 0) { return $false }
    $r = Invoke-Pine ([byte[]]@(0x09, $AutoSaveSlot))
    return ($r -and $r[4] -eq 0)
}

function Get-Pcsx2AutoState([string]$exe, $g) {
    # arquivo do slot automático: sstates\<SERIAL> (<CRC>).10.p2s
    $dir = Join-Path (Get-Pcsx2DataDir $exe) 'sstates'
    $serial = Get-GameSerial $g
    if (-not $serial -or -not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -File -Filter "$serial (*).$AutoSaveSlot.p2s" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Set-GameRunningFlag($g, [bool]$on) {
    # marca que o jogo está aberto; se o launcher não conseguir limpar (crash do jogo ou do PC), a marca fica
    if (-not $g) { return }
    if ($on) { $g | Add-Member -NotePropertyName running -NotePropertyValue $true -Force }
    elseif ($g.PSObject.Properties['running']) { $g.PSObject.Properties.Remove('running') }
    Save-Config
}

function Test-Ps2Dns([string]$dns) {
    return ($dns -match '^((25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(25[0-5]|2[0-4]\d|1?\d?\d)$')
}

function Repair-Ps2FileName($g) {
    # CHD com nome .iso: o PCSX2 decide pela extensão, não reconhece o disco e cai no menu do PS2
    if ($g.path -notmatch '(?i)\.iso$') { return }
    try {
        $fs = [IO.File]::OpenRead($g.path)
        try { $h = New-Object byte[] 8; [void]$fs.Read($h, 0, 8) } finally { $fs.Close() }
        if ([Text.Encoding]::ASCII.GetString($h) -ne 'MComprHD') { return }
        $new = [IO.Path]::ChangeExtension($g.path, '.chd')
        if (Test-Path -LiteralPath $new) { return }
        Move-Item -LiteralPath $g.path -Destination $new -ErrorAction Stop
        $g.path = $new
        Save-Config
    } catch {}
}

function Apply-Pcsx2Settings([string]$exe, $s) {
    $ini = Get-Pcsx2Ini $exe
    $dns = [string]$s.onlineDns
    # Tela: widescreen = patch 16:9 do próprio PCSX2 (jogos sem patch ficam esticados), stretch = esticar, original = 4:3
    $aspect = switch ($s.aspect) { 'stretch' { 'Stretch' } 'original' { 'Auto 4:3/3:2' } default { '16:9' } }
    Set-IniValues $ini ([ordered]@{
            # PINE: canal local do PCSX2 usado pelo save automático; BackupSavestate guarda o save anterior como .backup
            'EmuCore'            = [ordered]@{ EnableWideScreenPatches = ($s.aspect -notin 'stretch', 'original'); EnablePINE = ([int]$s.autosave -gt 0); PINESlot = $PineSlot; BackupSavestate = $true }
            'EmuCore/GS'         = [ordered]@{ Renderer = [int]$s.renderer; upscale_multiplier = [int]$s.scale; VsyncEnable = [bool]$s.vsync; OsdShowFPS = [bool]$s.showFps; AspectRatio = $aspect
                LoadTextureReplacements = [bool]$s.textures; LoadTextureReplacementsAsync = $true; MaxAnisotropy = [int]$s.aniso
                # Shade Boost: 50 = normal; o controle vai de -100% a +100%
                ShadeBoost = ([int]$s.saturation -ne 0); ShadeBoost_Saturation = [int](50 + [int]$s.saturation / 2)
            }
            'EmuCore/Speedhacks' = [ordered]@{ EECycleRate = [int]$s.eeCycle; vuThread = [bool]$s.mtvu; fastCDVD = [bool]$s.fastCdvd }
            'UI'                 = [ordered]@{ SettingsVersion = 1; StartFullscreen = [bool]$s.fullscreen }
            'Framerate'          = [ordered]@{ TurboScalar = [int]$s.turbo }
            'Achievements'       = [ordered]@{ UnlockSoundName = (Join-Path $Root 'sons\trofeu.wav') }
            # rede do PS2: Sockets funciona com Wi-Fi ou cabo, sem Npcap nem administrador. O DNS leva o jogo ao servidor da
            # comunidade, porque os servidores originais da Sony foram desligados. Desligado, só apaga a rede e preserva o resto
            'DEV9/Eth'           = $(if (Test-Ps2Dns $dns) { [ordered]@{ EthEnable = $true; EthApi = 'Sockets'; EthDevice = 'Auto'; InterceptDHCP = $true; AutoMask = $true; AutoGateway = $true; ModeDNS1 = 'Manual'; DNS1 = $dns; ModeDNS2 = 'Auto' } } else { [ordered]@{ EthEnable = $false } })
        })
    Set-Pcsx2Controllers $ini
    return $true
}

function Apply-Rpcs3Settings([string]$exe, [string]$titleId, $s) {
    $dir = Split-Path $exe
    # o RPCS3 toca este arquivo ao desbloquear um troféu
    try {
        $snd = Join-Path $dir 'sounds\snd_trophy.wav'
        if (-not (Test-Path -LiteralPath $snd)) {
            New-Item -ItemType Directory -Force (Split-Path $snd) | Out-Null
            Copy-Item -LiteralPath (Join-Path $Root 'sons\trofeu.wav') $snd -Force
        }
    } catch { Write-AppLog "Som de troféu do RPCS3: $($_.Exception.Message)" }
    # tela cheia fica nas configurações da interface do RPCS3
    Set-IniValues (Join-Path $dir 'GuiConfigs\CurrentSettings.ini') @{ 'Meta' = @{ startGameFullscreen = [bool]$s.fullscreen } } '='
    if (-not $titleId) { return $false }
    # configuração personalizada do jogo: o RPCS3 aplica por cima da configuração global
    $b = { param($v) ([bool]$v).ToString().ToLower() }
    $yaml = @"
Core:
  PPU Decoder: Recompiler (LLVM)
  SPU Decoder: Recompiler (LLVM)
  SPU Block Size: $($s.spuBlock)
Video:
  Renderer: $($s.renderer)
  Resolution Scale: $($s.scale)
  Anisotropic Filter Override: $([int]$s.aniso)
  Aspect ratio: 16:9
  Stretch To Display Area: $(& $b $s.stretch)
  Frame limit: $($s.frameLimit)
  Write Color Buffers: $(& $b $s.wcb)
  VSync: $(& $b $s.vsync)
  Performance Overlay:
    Enabled: $(& $b $s.showFps)
"@
    $cc = Join-Path $dir 'config\custom_configs'
    New-Item -ItemType Directory -Force $cc | Out-Null
    [IO.File]::WriteAllText((Join-Path $cc "config_$titleId.yml"), $yaml, (New-Object Text.UTF8Encoding($false)))
    return $true
}

# ---------------------------------------------------------------- desempenho

$script:PrevPowerScheme = $null

function Enable-PerfPowerPlan($s) {
    if (-not $s.powerPlan) { return }
    try {
        $out = (powercfg /getactivescheme) -join ' '
        if ($out -match '([0-9a-fA-F-]{36})') { $script:PrevPowerScheme = $Matches[1] }
        powercfg /setactive SCHEME_MIN | Out-Null   # "Alto desempenho"
    } catch {}
}

function Restore-PowerPlan {
    if ($script:PrevPowerScheme) {
        try { powercfg /setactive $script:PrevPowerScheme | Out-Null } catch {}
        $script:PrevPowerScheme = $null
    }
}

# Saturação no PS3/PS4: vibração digital da NVIDIA (NVAPI), ligada só durante o jogo.
# Só aumenta a saturação: o nível atual do driver é o mínimo.
$script:NvOk = $null

function Test-NvVibrance {
    if ($null -ne $script:NvOk) { return $script:NvOk }
    $script:NvOk = $false
    try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class NvDvc {
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr QueryInterface(uint id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumFn(int index, ref IntPtr handle);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetFn(IntPtr handle, int outputId, ref DvcInfo info);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SetFn(IntPtr handle, int outputId, int level);
    [StructLayout(LayoutKind.Sequential)] public struct DvcInfo { public uint version; public int current, min, max; }
    static T Fn<T>(uint id) where T : class {
        IntPtr p = QueryInterface(id);
        return p == IntPtr.Zero ? null : (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
    }
    public static bool Init() { var f = Fn<InitFn>(0x0150E828); return f != null && f() == 0; }
    public static List<IntPtr> Displays() {
        var list = new List<IntPtr>(); var f = Fn<EnumFn>(0x9ABDD40D);
        for (int i = 0; f != null && i < 8; i++) { IntPtr h = IntPtr.Zero; if (f(i, ref h) != 0) break; list.Add(h); }
        return list;
    }
    public static int[] Get(IntPtr h) {
        var info = new DvcInfo(); info.version = (uint)(Marshal.SizeOf(typeof(DvcInfo)) | (1 << 16));
        var f = Fn<GetFn>(0x4085DE45);
        if (f == null || f(h, 0, ref info) != 0) return null;
        return new int[] { info.current, info.min, info.max };
    }
    public static bool Set(IntPtr h, int level) { var f = Fn<SetFn>(0x172409B4); return f != null && f(h, 0, level) == 0; }
}
'@
        $script:NvOk = [NvDvc]::Init() -and ([NvDvc]::Displays().Count -gt 0)
    } catch {}
    return $script:NvOk
}

function Enable-Vibrance([int]$pct) {
    if ($pct -le 0 -or -not (Test-NvVibrance)) { return }
    Restore-Vibrance
    $saved = @()
    foreach ($h in [NvDvc]::Displays()) {
        $info = [NvDvc]::Get($h)
        if (-not $info) { $saved += $null; continue }
        $saved += $info[0]
        [void][NvDvc]::Set($h, [int][math]::Round($info[0] + ($info[2] - $info[0]) * $pct / 100))
    }
    # guardado no config: se o launcher fechar no meio do jogo, a cor volta ao normal na próxima abertura
    $script:Cfg.restoreVibrance = $saved
    Save-Config
}

function Restore-Vibrance {
    if (-not $script:Cfg.restoreVibrance -or -not (Test-NvVibrance)) { return }
    $saved = @($script:Cfg.restoreVibrance)
    $i = 0
    foreach ($h in [NvDvc]::Displays()) {
        if ($i -lt $saved.Count -and $null -ne $saved[$i]) { [void][NvDvc]::Set($h, [int]$saved[$i]) }
        $i++
    }
    $script:Cfg.restoreVibrance = $null
    Save-Config
}

# Volume do jogo: muda só o volume do emulador no mixer do Windows (vale para qualquer emulador).
# Durante o jogo: - / + (teclado numérico ou ao lado do Backspace) diminuem/aumentam de 10 em 10%.
$script:AudioOk = $false
try {
    Add-Type -ErrorAction Stop -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace PL {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo {}
    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator { int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices); }
    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection { int GetCount(out int n); int Item(int i, out IMMDevice device); }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice { int Activate(ref Guid iid, int clsCtx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); }
    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 { int R0(); int R1(); int GetSessionEnumerator(out IAudioSessionEnumerator e); }
    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator { int GetCount(out int n); int GetSession(int i, out IAudioSessionControl2 s); }
    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        int R0(); int R1(); int R2(); int R3(); int R4(); int R5(); int R6(); int R7(); int R8(); int R9(); int R10();
        int GetProcessId(out uint pid);
    }
    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume { int SetMasterVolume(float level, ref Guid ctx); int GetMasterVolume(out float level); }

    public static class Audio {
        // aplica o volume (0-100) em todas as sessões de áudio desses processos; devolve quantas achou
        public static int SetVolume(int[] pids, int pct) {
            var set = new HashSet<uint>(); foreach (int p in pids) set.Add((uint)p);
            int found = 0; Guid ctx = Guid.Empty, iid = typeof(IAudioSessionManager2).GUID;
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
            IMMDeviceCollection devs; en.EnumAudioEndpoints(0, 1, out devs);   // saída, ativos
            int n; devs.GetCount(out n);
            for (int i = 0; i < n; i++) {
                try {
                    IMMDevice dev; devs.Item(i, out dev);
                    object o; dev.Activate(ref iid, 23, IntPtr.Zero, out o);
                    IAudioSessionEnumerator se; ((IAudioSessionManager2)o).GetSessionEnumerator(out se);
                    int c; se.GetCount(out c);
                    for (int j = 0; j < c; j++) {
                        IAudioSessionControl2 s; se.GetSession(j, out s);
                        uint pid; s.GetProcessId(out pid);
                        if (!set.Contains(pid)) continue;
                        ((ISimpleAudioVolume)s).SetMasterVolume(pct / 100f, ref ctx);
                        found++;
                    }
                } catch {}
            }
            return found;
        }

        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        public static bool KeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
        public static int ForegroundPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return (int)pid; }
    }

    // aviso "Volume 70%" por cima do jogo, sem roubar o foco
    public class Osd : Form {
        static Osd inst; int value; Timer hide;
        public static string MuteText = "Volume: mudo";
        Osd() {
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
            StartPosition = FormStartPosition.Manual; Size = new Size(260, 64);
            BackColor = Color.FromArgb(24, 24, 32); DoubleBuffered = true;
            hide = new Timer(); hide.Interval = 1500; hide.Tick += delegate { hide.Stop(); Hide(); };
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80 | 0x8; return cp; }   // noactivate, toolwindow, topmost
        }
        protected override void OnPaint(PaintEventArgs e) {
            var g = e.Graphics; g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using (var f = new Font("Segoe UI", 12f, FontStyle.Bold))
                g.DrawString(value == 0 ? MuteText : "Volume " + value + "%", f, Brushes.White, 14, 8);
            using (var b = new SolidBrush(Color.FromArgb(60, 60, 75))) g.FillRectangle(b, 16, 40, 228, 10);
            using (var b = new SolidBrush(Color.FromArgb(124, 92, 255))) g.FillRectangle(b, 16, 40, 228 * value / 100, 10);
        }
        public static void ShowValue(int pct, IntPtr gameWindow) {
            if (inst == null || inst.IsDisposed) inst = new Osd();
            inst.value = pct;
            var scr = gameWindow != IntPtr.Zero ? Screen.FromHandle(gameWindow) : Screen.PrimaryScreen;
            inst.Location = new Point(scr.Bounds.Left + (scr.Bounds.Width - inst.Width) / 2, scr.Bounds.Top + 40);
            if (!inst.Visible) inst.Show();
            inst.TopMost = true; inst.Invalidate();
            inst.hide.Stop(); inst.hide.Start();
        }
    }
}
'@
    $script:AudioOk = $true
    [PL.Osd]::MuteText = L 'Volume: mudo'
} catch {}

# aviso de conquista animado, por cima do jogo; separado do bloco acima para uma falha aqui não afetar o volume
$script:TrophyPopOk = $false
try {
    Add-Type -ErrorAction Stop -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Media;
using System.Windows.Forms;

namespace PL {
    // entra deslizando pela direita, o troféu "salta", um brilho passa pelo cartão e ele sai; um por vez, em fila
    public class TrophyPop : Form {
        class Item { public string Grade, Name, Game, Cover, Sound; public Color Tint; public IntPtr Win; }
        const int CardW = 430, CardH = 104, EnterMs = 420, HoldMs = 5200, LeaveMs = 320;
        static TrophyPop inst;
        static readonly Queue<Item> queue = new Queue<Item>();
        Item cur; Image cover; SoundPlayer player; Point home;
        readonly Timer tick = new Timer();
        readonly Stopwatch clock = new Stopwatch();

        TrophyPop() {
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
            StartPosition = FormStartPosition.Manual; Size = new Size(CardW, CardH);
            BackColor = Color.FromArgb(26, 27, 34); DoubleBuffered = true;
            using (var p = Round(new Rectangle(0, 0, CardW, CardH), 16)) Region = new Region(p);
            tick.Interval = 15; tick.Tick += OnTick;
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get { var cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x80 | 0x8 | 0x20; return cp; }   // sem foco, sem barra de tarefas, sempre em cima, o clique atravessa
        }

        public static void Enqueue(string grade, string name, string game, string coverPath, int argb, string soundPath, IntPtr gameWindow) {
            queue.Enqueue(new Item { Grade = grade, Name = name, Game = game, Cover = coverPath, Sound = soundPath, Tint = Color.FromArgb(argb), Win = gameWindow });
            if (inst == null || inst.IsDisposed) inst = new TrophyPop();
            if (inst.cur == null) inst.Next();
        }

        void Next() {
            if (queue.Count == 0) { cur = null; return; }
            var item = queue.Dequeue();
            // troca a capa antes de liberar a antiga: uma pintura no meio nunca vê imagem liberada
            Image next = null;
            try { if (!string.IsNullOrEmpty(item.Cover) && System.IO.File.Exists(item.Cover)) using (var i = Image.FromFile(item.Cover)) next = new Bitmap(i); } catch { }
            var old = cover; cover = next; cur = item;
            if (old != null) old.Dispose();
            var scr = cur.Win != IntPtr.Zero ? Screen.FromHandle(cur.Win) : Screen.PrimaryScreen;
            home = new Point(scr.Bounds.Right - CardW - 32, scr.Bounds.Top + 32);
            Location = new Point(home.X + 70, home.Y); Opacity = 0;
            if (!Visible) Show();
            TopMost = true;
            clock.Restart(); tick.Start();
            // carregado uma vez só: ler o arquivo na hora de tocar travaria a animação
            try {
                if (!string.IsNullOrEmpty(cur.Sound)) {
                    if (player == null || player.SoundLocation != cur.Sound) { if (player != null) player.Dispose(); player = new SoundPlayer(cur.Sound); player.Load(); }
                    player.Play();
                }
            } catch { }
        }

        void OnTick(object sender, EventArgs e) {
            double t = clock.ElapsedMilliseconds;
            try {
                if (t < EnterMs) {
                    double k = 1 - Math.Pow(1 - t / EnterMs, 3);
                    Left = home.X + (int)((1 - k) * 70); Opacity = k * 0.97;
                } else if (t < EnterMs + HoldMs) {
                    if (Left != home.X) { Left = home.X; Opacity = 0.97; }
                } else if (t < EnterMs + HoldMs + LeaveMs) {
                    double k = (t - EnterMs - HoldMs) / LeaveMs;
                    Left = home.X + (int)(k * k * 70); Opacity = (1 - k) * 0.97;
                } else {
                    tick.Stop(); Hide(); cur = null; Next();
                    return;
                }
                if (t < 1600) Invalidate();
            } catch { tick.Stop(); Hide(); cur = null; }
        }

        static GraphicsPath Round(Rectangle r, int rad) {
            var p = new GraphicsPath(); int d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }

        static void DrawCup(Graphics g, float x, float y, float s, Color c) {
            using (var b = new SolidBrush(c))
            using (var pen = new Pen(c, Math.Max(1.5f, s * 0.07f)))
            using (var bowl = new GraphicsPath()) {
                bowl.AddBezier(x + .22f * s, y, x + .22f * s, y + .5f * s, x + .4f * s, y + .58f * s, x + .5f * s, y + .58f * s);
                bowl.AddBezier(x + .5f * s, y + .58f * s, x + .6f * s, y + .58f * s, x + .78f * s, y + .5f * s, x + .78f * s, y);
                bowl.CloseFigure();
                g.FillPath(b, bowl);
                g.DrawArc(pen, x + .06f * s, y + .04f * s, .26f * s, .3f * s, 90, 180);
                g.DrawArc(pen, x + .68f * s, y + .04f * s, .26f * s, .3f * s, 270, 180);
                g.FillRectangle(b, x + .45f * s, y + .56f * s, .1f * s, .24f * s);
                g.FillRectangle(b, x + .3f * s, y + .8f * s, .4f * s, .1f * s);
            }
        }

        public static string LastError;
        // erro aqui viraria um X vermelho permanente no cartão
        protected override void OnPaint(PaintEventArgs e) {
            if (cur == null) return;
            try { Draw(e.Graphics); } catch (Exception ex) { LastError = ex.ToString(); }
        }

        void Draw(Graphics g) {
            g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            double t = clock.ElapsedMilliseconds;
            using (var bg = new LinearGradientBrush(ClientRectangle, Color.FromArgb(38, 39, 49), Color.FromArgb(20, 21, 27), 90f)) g.FillRectangle(bg, ClientRectangle);
            using (var edge = new Pen(Color.FromArgb(70, cur.Tint), 2f))
            using (var p = Round(new Rectangle(1, 1, CardW - 3, CardH - 3), 15)) g.DrawPath(edge, p);

            var box = new Rectangle(16, 16, 72, 72);
            using (var clip = Round(box, 10)) {
                if (cover != null) {
                    var keep = g.Clip; g.SetClip(clip, CombineMode.Intersect);
                    int side = Math.Min(cover.Width, cover.Height);
                    g.DrawImage(cover, box, new Rectangle((cover.Width - side) / 2, (cover.Height - side) / 2, side, side), GraphicsUnit.Pixel);
                    g.Clip = keep;
                } else using (var b = new SolidBrush(Color.FromArgb(48, 50, 62))) g.FillPath(b, clip);
            }
            // o troféu aparece maior e assenta
            double a = Math.Min(1, t / 520), pop = a < .7 ? 1.3 * (a / .7) : 1.3 - .3 * ((a - .7) / .3);
            float size = Math.Max(8f, (float)(38 * pop)), cx = 80, cy = 78;   // tamanho zero faria o desenho falhar
            using (var disc = new SolidBrush(Color.FromArgb(235, 20, 21, 27))) g.FillEllipse(disc, cx - size * .68f, cy - size * .68f, size * 1.36f, size * 1.36f);
            DrawCup(g, cx - size / 2, cy - size / 2 + size * .04f, size, cur.Tint);

            var left = 104; var width = CardW - left - 16;
            var fmt = new StringFormat(StringFormatFlags.NoWrap) { Trimming = StringTrimming.EllipsisCharacter };
            using (var f = new Font("Segoe UI", 9.5f, FontStyle.Bold))
            using (var b = new SolidBrush(cur.Tint)) g.DrawString(cur.Grade, f, b, new RectangleF(left, 13, width, 20), fmt);
            using (var f = new Font("Segoe UI Semibold", 14f)) g.DrawString(cur.Name, f, Brushes.White, new RectangleF(left, 33, width, 30), fmt);
            using (var f = new Font("Segoe UI", 9.5f))
            using (var b = new SolidBrush(Color.FromArgb(165, 168, 182))) g.DrawString(cur.Game, f, b, new RectangleF(left, 68, width, 20), fmt);

            // brilho que atravessa o cartão
            if (t > 450 && t < 1250) {
                float x = (float)(-140 + (t - 450) / 800 * (CardW + 280));
                var band = new RectangleF(x, 0, 140, CardH);
                using (var br = new LinearGradientBrush(band, Color.Transparent, Color.Transparent, 0f)) {
                    var cb = new ColorBlend();
                    cb.Colors = new[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(46, 255, 255, 255), Color.FromArgb(0, 255, 255, 255) };
                    cb.Positions = new[] { 0f, .5f, 1f };
                    br.InterpolationColors = cb;
                    g.FillRectangle(br, band);
                }
            }
        }
    }
}
'@
    $script:TrophyPopOk = $true
} catch {}

# troca de tela sem piscar: congela a janela, monta tudo por trás e mostra de uma vez
$script:UiFreezeOk = $false
try {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PL {
    public static class UiFreeze {
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
        [DllImport("user32.dll")] static extern bool RedrawWindow(IntPtr h, IntPtr r, IntPtr rg, uint f);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateFileMapping(IntPtr f, IntPtr a, uint p, uint hi, uint lo, IntPtr n);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        // pede e devolve na hora a memória virtual; se faltar, o próprio Windows aumenta o arquivo de paginação
        public static int TryCommit(double gb) {
            ulong s = (ulong)(gb * 1024 * 1024 * 1024);
            IntPtr h = CreateFileMapping(new IntPtr(-1), IntPtr.Zero, 0x08000004, (uint)(s >> 32), (uint)s, IntPtr.Zero);   // PAGE_READWRITE | SEC_COMMIT
            if (h == IntPtr.Zero) return Marshal.GetLastWin32Error();
            CloseHandle(h);
            return 0;
        }
        const int WM_SETREDRAW = 0x000B;
        public static void Stop(IntPtr h) { SendMessage(h, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero); }
        public static void Resume(IntPtr h) {
            SendMessage(h, WM_SETREDRAW, (IntPtr)1, IntPtr.Zero);
            RedrawWindow(h, IntPtr.Zero, IntPtr.Zero, 0x1 | 0x4 | 0x80 | 0x100 | 0x400);   // tudo, filhos incluídos, agora
        }
    }
}
'@
    $script:UiFreezeOk = $true
} catch {}

function Invoke-UiFrozen([scriptblock]$work) {
    if ($script:UiFrozen -or -not $script:UiFreezeOk -or -not $form.IsHandleCreated) { & $work; return }
    $script:UiFrozen = $true
    [PL.UiFreeze]::Stop($form.Handle)
    # finally: janela congelada para sempre seria pior do que qualquer piscada
    try { & $work } finally { [PL.UiFreeze]::Resume($form.Handle); $script:UiFrozen = $false }
}

$script:RunVolume = 100
$script:RunGame = $null
$script:RunPids = @()
$script:VolKeyHeld = 0

function Set-GameVolume([int]$pct, [bool]$osd) {
    $script:RunVolume = [math]::Max(0, [math]::Min(100, $pct))
    if (-not $script:AudioOk -or $script:RunPids.Count -eq 0) { return }
    try { [void][PL.Audio]::SetVolume([int[]]$script:RunPids, $script:RunVolume) } catch {}
    if ($osd) {
        $h = [IntPtr]::Zero
        foreach ($p in (Get-RunProcs)) { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
        try { [PL.Osd]::ShowValue($script:RunVolume, $h) } catch {}
    }
}

# ---------------------------------------------------------------- iniciar jogo

# O jogo é acompanhado pela pasta do emulador: qualquer processo rodando de lá conta.
# Assim funciona também com programas que abrem o jogo e fecham em seguida.
$script:RunDir = $null
$script:RunMode = 'game'   # game | setup
$script:RunPriority = $false
$script:EmptyTicks = 0

function Get-RunProcs {
    if (-not $script:RunDir) { return @() }
    $d = $script:RunDir.ToLower().TrimEnd('\') + '\'
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.ToLower().StartsWith($d) }
}

function Test-ConsoleExe([string]$exe) {
    # subsistema do .exe (cabeçalho PE): 3 = programa de console, que abre uma janela preta de log junto
    try {
        $fs = [IO.File]::OpenRead($exe)
        try { $b = New-Object byte[] 1024; [void]$fs.Read($b, 0, 1024) } finally { $fs.Close() }
        $pe = [BitConverter]::ToInt32($b, 0x3c)
        return ([BitConverter]::ToUInt16($b, $pe + 92) -eq 3)
    } catch { return $false }
}

function Start-Emu([string]$exe, [string[]]$argList, [string]$mode, $s) {
    $wd = Split-Path $exe
    # a animação cobre a tela antes de o emulador nascer: a janela dele surge em menos de meio segundo
    if ($mode -eq 'game') {
        Show-LaunchOverlay $script:RunGame $exe
    }
    try {
        if ($mode -eq 'game' -and (Test-ConsoleExe $exe)) {
            # shadPS4: só a janela do jogo, sem a janela preta do log (o log continua indo para o arquivo dele)
            $psi = New-Object Diagnostics.ProcessStartInfo $exe
            $psi.Arguments = ($argList -join ' ')
            $psi.WorkingDirectory = $wd
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $script:RunProc = [Diagnostics.Process]::Start($psi)
        } elseif ($argList -and $argList.Count -gt 0) {
            $script:RunProc = Start-Process -FilePath $exe -ArgumentList ($argList -join ' ') -WorkingDirectory $wd -PassThru
        } else {
            $script:RunProc = Start-Process -FilePath $exe -WorkingDirectory $wd -PassThru
        }
    } catch { Close-LaunchOverlay; throw }
    try { [void]$script:RunProc.Handle } catch {}   # segura o handle para conseguir ler o código de saída depois
    $script:RunDir = $wd
    $script:RunEmuExe = $exe
    $script:RunMode = $mode
    $script:RunPriority = ($mode -eq 'game') -and $s -and [bool]$s.highPriority
    $script:EmptyTicks = 0
    $script:Focused = $false
    $script:RunStart = Get-Date   # para somar o tempo jogado
    if ($mode -eq 'game') { $form.WindowState = 'Minimized' }
    if ($mode -eq 'game' -and $s -and $s.nvVibrance) { Enable-Vibrance ([int]$s.saturation) }
    $script:RunPids = @()
    $script:RunVolume = 100
    if ($mode -eq 'game' -and $s -and $null -ne $s.volume) { $script:RunVolume = [int]$s.volume }
    $timer.Start()
    if ($mode -eq 'game' -and $script:AudioOk) { $volTimer.Start() }
}

function Require-Emu([string]$key) {
    $exe = $script:Cfg[$key]
    if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    $r = [PL.Lang]::Msg(
        "$($EmuInfo[$key].label) não está instalado.`nAbrir a janela de emuladores para instalar?", 'Trivium Hub', 'YesNo')
    if ($r -eq 'Yes') { Show-EmulatorsDialog }
    $exe = $script:Cfg[$key]
    if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    return $null
}

function Get-NativePort($g) {
    if ($g.console -ne 'PS4') { return $null }
    $tid = Get-Ps4TitleId $g.path
    foreach ($p in $NativePorts) {
        if ($tid -in $p.ids -or $g.name -match [regex]::Escape($p.match)) { return $p }
    }
    return $null
}

function Test-PortConfigured($port, [string]$portDir, [string]$gameDir) {
    # o port guarda a pasta do jogo nas configurações dele; procuramos o caminho lá dentro
    $files = @($port.cfg | ForEach-Object { Join-Path $portDir $_ } | Where-Object { Test-Path -LiteralPath $_ })
    if ($port.appdata) {
        $ad = Join-Path $env:APPDATA $port.appdata
        if (Test-Path -LiteralPath $ad) {
            $files += @(Get-ChildItem -LiteralPath $ad -Recurse -File -Include *.json, *.ini, *.toml, *.cfg, *.txt -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -lt 2MB } | ForEach-Object FullName)
        }
    }
    $want = $gameDir.ToLower().TrimEnd('\')
    foreach ($f in $files) {
        $txt = ((Get-Content -LiteralPath $f -Raw) -replace '\\\\', '\' -replace '/', '\').ToLower()
        if ($txt.Contains($want)) { return $true }
    }
    return $false
}

function Open-PortSetup($port, $g) {
    $exe = $script:Cfg[$port.key]
    $script:RunGame = $g
    [System.Windows.Forms.Clipboard]::SetText($g.path)
    [void][PL.Lang]::Msg("$($port.setup)`n`nDa próxima vez o Trivium Hub abre o jogo direto.", 'Trivium Hub')
    Start-Emu $exe @() 'game' (Get-GameSettings $g)
    Set-Status "$($port.name) aberto: $($g.name)"
}

function Initialize-Shadps4Users([string]$exe) {
    # O shadPS4 (0.20+) pergunta "Save Migration" (copiar/mover saves antigos) sempre que a pasta do usuário
    # user\home\1000 ainda não existe, mesmo sem save nenhum. Criando as pastas antes, ele não pergunta;
    # se houver saves no lugar antigo (user\savedata\1, versões antigas), o launcher copia sozinho.
    $user = Join-Path (Split-Path $exe) 'user'
    if (-not (Test-Path -LiteralPath $user)) { $user = Join-Path $env:APPDATA 'shadPS4' }
    $home1 = Join-Path $user 'home\1000'
    if (Test-Path -LiteralPath $home1) { return }
    foreach ($id in 1000, 1001, 1002, 1003) {
        foreach ($sub in 'savedata', 'trophy', 'inputs') { New-Item -ItemType Directory -Force (Join-Path $user "home\$id\$sub") | Out-Null }
    }
    $old = Join-Path $user 'savedata\1'
    if ((Test-Path -LiteralPath $old) -and @(Get-ChildItem -LiteralPath $old -Force -ErrorAction SilentlyContinue).Count) {
        # copia (não move): o lugar antigo continua como estava
        try { Copy-Item -Path (Join-Path $old '*') -Destination (Join-Path $home1 'savedata') -Recurse -Force -ErrorAction Stop }
        catch { Write-AppLog "shadPS4: não copiou os saves antigos ($old): $($_.Exception.Message)" }
    }
}

function Apply-Shadps4Settings([string]$exe, [string]$tid, $s) {
    # configuração só deste jogo: user\custom_configs\<CUSA>.json, aplicada pelo shadPS4 por cima da global.
    # Mantém o que já existir no arquivo (ajustes feitos no próprio shadPS4) e troca só estas chaves.
    if (-not $tid) { return }
    $user = Join-Path (Split-Path $exe) 'user'
    if (-not (Test-Path -LiteralPath $user)) { $user = Join-Path $env:APPDATA 'shadPS4' }
    $dir = Join-Path $user 'custom_configs'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $path = Join-Path $dir "$tid.json"
    $j = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path) { try { $j = [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch {} }
    # patch extra ligado que pede mais memória: garante o mínimo (sem isso o jogo fecha)
    $dmem = [int]$s.dmem; $vblank = [int]$s.vblank
    foreach ($ex in @(Get-ExtraPs4Patches $tid) + @(Get-Ps4PatchSets $tid)) {
        if (-not $s[$ex.key]) { continue }
        if ($ex.dmem -and $dmem -lt $ex.dmem) { $dmem = $ex.dmem }
        if ($ex.vblank -and $vblank -lt $ex.vblank) { $vblank = $ex.vblank }
    }
    $values = [ordered]@{
        # sempre sem borda: nada do Windows aparece por cima de tela cheia exclusiva, nem o aviso de conquista
        # com a animação de abertura o jogo nasce em janela (o argumento --fullscreen não vence esta chave)
        GPU     = [ordered]@{ full_screen = ([bool]$s.fullscreen -and -not $script:PlayFxOk); full_screen_mode = 'Fullscreen (Borderless)'; present_mode = [string]$s.present
            vblank_frequency = $vblank; readbacks_mode = [int]$s.readbacks; fsr_enabled = [bool]$s.fsr; rcas_enabled = [bool]$s.rcas
            copy_gpu_buffers = [bool]$s.copyBuffers; readback_linear_images_enabled = [bool]$s.linearImages
            direct_memory_access_enabled = [bool]$s.dma
        }
        General = [ordered]@{ neo_mode = [bool]$s.neo; extra_dmem_in_mbytes = $dmem; console_language = [int]$s.language
            trophy_popup_disabled = -not [bool]$s.trophyPopup
        }
        Input   = [ordered]@{ is_circle_enter = [bool]$s.circleEnter }
        # async_shader_recompiling só existe no eltutz (o oficial ignora a chave)
        Vulkan  = [ordered]@{ pipeline_cache_enabled = [bool]$s.pipelineCache; async_shader_recompiling = [bool]$s.eltutz }
    }
    foreach ($grp in $values.Keys) {
        if (-not $j.PSObject.Properties[$grp]) { $j | Add-Member -NotePropertyName $grp -NotePropertyValue ([pscustomobject]@{}) }
        foreach ($k in $values[$grp].Keys) { $j.$grp | Add-Member -NotePropertyName $k -NotePropertyValue $values[$grp][$k] -Force }
    }
    [IO.File]::WriteAllText($path, ($j | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))

    Set-Ps4SkipPatches $user $tid $s
}

# nomes dos patches de pular: "Skip Intro", "Skip Any Video With X Button", "Skip Logo Videos", "Intro Skip"...
$SkipPatchPattern = '(?i)skip\s*(any\s*)?(intro|logo|video|movie|cutscene|cinematic|splash)|intro\s*skip'

# patches de jogos que não estão no repositório do shadPS4: entram no arquivo de patches do jogo e
# ligam/desligam pela opção "key" da tela de configurações (o shadPS4 só aplica na versão AppVer do jogo)
$ExtraPs4Patches = @(
    # God of War III Remastered 01.02: "Texture Corruption Fix" de cuesta4 (o mesmo usado no SpartanPort).
    # Aumenta a área de vídeo do jogo para texturas e efeitos; precisa de +2 GB de memória (dmem) ou o jogo fecha.
    @{ ids = @('CUSA01623', 'CUSA01715', 'CUSA01720', 'CUSA01740'); key = 'textureFix'; dmem = 2048
        xml = '<Metadata Title="God of War III Remastered" Name="Bug Fix - Texture Corruption Fix" Note="Fixes corrupted textures by increasing the Video Arena size. Requires 2048 MB of extra DMEM." Author="cuesta4" PatchVer="1.0" AppVer="01.02" AppElf="eboot.bin" isEnabled="false"><PatchList><Line Type="bytes" Address="0x007cd918" Value="00000090" /></PatchList></Metadata>'
    },
    # God of War III Remastered 01.02: 120 FPS de kvicken (limite do motor 59,94 -> 120 e a física continua na conta de 60);
    # precisa do vblank em 120. Endereços conferidos no eboot.bin do CUSA01623 01.02.
    @{ ids = @('CUSA01623', 'CUSA01715'); key = 'fps120'; vblank = 120
        xml = '<Metadata Title="God of War III Remastered" Name="Frame Rate Patch - 120 FPS" Note="Raises the engine maximum framerate from 59.94 to 120 FPS. Requires VBlank 120." Author="kvicken" PatchVer="1.1" AppVer="01.02" AppElf="eboot.bin" isEnabled="false"><PatchList><Line Type="bytes" Address="0x0048ff0a" Value="488d05e7c22600" /><Line Type="bytes" Address="0x0075dd04" Value="0000f042" /></PatchList></Metadata>'
    }
)

# o shadPS4 eltutz é compilado para Ryzen 5000 e precisa de AVX2 (sem isso fecha ao abrir o jogo)
Add-Type -Namespace PL -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] static extern bool IsProcessorFeaturePresent(uint f); public static bool HasAvx2() { return IsProcessorFeaturePresent(40); }'

# patches que já vêm no arquivo oficial do shadPS4: aqui só escolhe quais ficam ligados (pelo nome).
# off: patches que precisam ficar desligados quando a opção liga (ex: só um patch de FPS por vez).
# intel: só ligam em processador Intel (correções de travamento e de cor que só acontecem nele).
$BloodborneIds = @('CUSA00207', 'CUSA00208', 'CUSA00299', 'CUSA00900', 'CUSA01363', 'CUSA03014', 'CUSA03023', 'CUSA03173')
$Ps4PatchSets = @(
    # Bloodborne 1.09: os mesmos patches que o Bloodborne PC (Supermedo) deixa ligados, sem os que só fazem sentido
    # dentro do port (FPS destravado com o controle de quadros dele, reflexos SSR que pesam e resolução ultrawide)
    @{ ids = $BloodborneIds; key = 'communityFix'; appVer = '01.09'
        names = @('Performance Patch (Perf Increase)', 'Disable Motion Blur (Perf Increase)', 'Disable Dynamic Light Shadows (Perf Increase)',
            'Disable Chromatic Aberration', 'Disable AA', 'Disable DoF', 'Disable SSAO', 'Lower object/corpse physics', 'lower specific renders (Perf Increase)')
        intel = @('Intel 12th Gen+ SFX workaround', 'Intel Black Tonemap Fix')
        off = @('Enable Screen Space Reflections (READ NOTE)')
    },
    @{ ids = $BloodborneIds; key = 'fps60'; appVer = '01.09'
        names = @('60 FPS++')
        off = @('30 FPS++', '60FPS++ (no deltatime)', '120 FPS++', 'Uncap FPS++')
    },
    # 90 FPS++ (Kyo, yogesh1239): pede o vblank em 90; vem depois do 60, então se os dois estiverem marcados vale o 90.
    # (o 120 FPS++ ficou de fora: fechava o jogo ao entrar no mapa)
    @{ ids = $BloodborneIds; key = 'fps90'; appVer = '01.09'; vblank = 90
        names = @('90 FPS++')
        off = @('30 FPS++', '60FPS++ (no deltatime)', '60 FPS++', '120 FPS++', 'Uncap FPS++')
    }
)

function Get-ExtraPs4Patches([string]$tid) {
    return @($ExtraPs4Patches | Where-Object { $_.ids -contains $tid })
}

function Get-Ps4PatchSets([string]$tid) {
    return @($Ps4PatchSets | Where-Object { $_.ids -contains $tid })
}

function Get-Ps4PatchKeys([string]$tid) {
    # opções de patch que este jogo tem (para mostrar "120 FPS" / "60 FPS" só onde existe)
    return @(@(Get-ExtraPs4Patches $tid) + @(Get-Ps4PatchSets $tid) | ForEach-Object { $_.key } | Select-Object -Unique)
}

function Test-IntelCpu {
    if ($null -eq $script:IsIntelCpu) { try { $script:IsIntelCpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer -match 'Intel' } catch { $script:IsIntelCpu = $false } }
    return $script:IsIntelCpu
}

function Set-Ps4SkipPatches([string]$user, [string]$tid, $s) {
    $on = [bool]$s.skipVideos
    # patches da comunidade (app\patches-ps4) ficam em user\patches\shadPS4, que o shadPS4 carrega sozinho;
    # aqui só liga/desliga os de pular vídeo/intro do jogo (os outros ficam como estão)
    $src = Join-Path $Root 'patches-ps4'
    if (-not (Test-Path -LiteralPath (Join-Path $src 'files.json'))) { return }
    $dst = Join-Path $user 'patches\shadPS4'
    New-Item -ItemType Directory -Force $dst | Out-Null
    foreach ($f in Get-ChildItem -LiteralPath $src -File) {
        $d = Join-Path $dst $f.Name
        # copia os novos e os atualizados pelo instalador (os já ajustados aqui ficam mais novos e são mantidos)
        if (-not (Test-Path -LiteralPath $d) -or (Get-Item -LiteralPath $d).LastWriteTime -lt $f.LastWriteTime) { Copy-Item -LiteralPath $f.FullName $d -Force }
    }
    $index = [IO.File]::ReadAllText((Join-Path $dst 'files.json')) | ConvertFrom-Json
    $file = $index.PSObject.Properties | Where-Object { @($_.Value) -contains $tid } | Select-Object -First 1
    if (-not $file) { return }
    $xmlPath = Join-Path $dst $file.Name
    $doc = New-Object Xml.XmlDocument; $doc.PreserveWhitespace = $true
    $doc.Load($xmlPath)
    $changed = $false
    foreach ($m in $doc.SelectNodes('/Patch/Metadata')) {
        if ($m.GetAttribute('Name') -notmatch $SkipPatchPattern) { continue }
        $want = if ($on) { 'true' } else { 'false' }
        if ($m.GetAttribute('isEnabled') -ne $want) { $m.SetAttribute('isEnabled', $want); $changed = $true }
    }
    foreach ($ex in (Get-ExtraPs4Patches $tid)) {
        $frag = New-Object Xml.XmlDocument; $frag.LoadXml($ex.xml)
        $name = $frag.DocumentElement.GetAttribute('Name')
        $m = $doc.SelectNodes('/Patch/Metadata') | Where-Object { $_.GetAttribute('Name') -eq $name } | Select-Object -First 1
        if (-not $m) { $m = $doc.DocumentElement.AppendChild($doc.ImportNode($frag.DocumentElement, $true)); $changed = $true }
        $want = if ($s[$ex.key]) { 'true' } else { 'false' }
        if ($m.GetAttribute('isEnabled') -ne $want) { $m.SetAttribute('isEnabled', $want); $changed = $true }
    }
    foreach ($set in (Get-Ps4PatchSets $tid)) {
        $on = [bool]$s[$set.key]
        $names = @($set.names); if (Test-IntelCpu) { $names += @($set.intel) }
        foreach ($m in $doc.SelectNodes('/Patch/Metadata')) {
            $n = $m.GetAttribute('Name')
            $want = $null
            if ($n -in $names) { $want = if ($on) { 'true' } else { 'false' } }
            elseif ($on -and $n -in @($set.off)) { $want = 'false' }
            if ($want -and $m.GetAttribute('isEnabled') -ne $want) { $m.SetAttribute('isEnabled', $want); $changed = $true }
        }
    }
    if ($changed) {
        $ws = New-Object Xml.XmlWriterSettings; $ws.Encoding = New-Object Text.UTF8Encoding($false)
        $w = [Xml.XmlWriter]::Create($xmlPath, $ws); $doc.Save($w); $w.Close()
    }
}

function Set-Shadps4FpsCorner([string]$user, [bool]$fullscreen) {
    # o contador de FPS do shadPS4 ("Video Info") guarda a posição em pixels no imgui.ini: a posição de uma janela
    # de 1280 cai no meio da tela cheia. Antes de abrir, coloca no canto de cima à direita do tamanho que o jogo vai ter.
    $ini = Join-Path $user 'imgui.ini'
    if (-not (Test-Path -LiteralPath $ini)) { return }
    $w = 1280   # janela padrão do shadPS4
    if ($fullscreen) { $w = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width }
    $lines = [IO.File]::ReadAllLines($ini)
    $in = $false; $size = 106; $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('[')) { $in = $lines[$i] -eq '[Window][Video Info]'; continue }
        if (-not $in) { continue }
        if ($lines[$i] -match '^Size=(\d+),') { $size = [int]$Matches[1] }
    }
    $x = [math]::Max(0, $w - $size - 8)
    $in = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('[')) { $in = $lines[$i] -eq '[Window][Video Info]'; continue }
        if ($in -and $lines[$i] -match '^Pos=') {
            $new = "Pos=$x,4"
            if ($lines[$i] -ne $new) { $lines[$i] = $new; $changed = $true }
        }
    }
    if ($changed) { [IO.File]::WriteAllLines($ini, $lines) }
}

function Get-Ps4PkgInstallDirs {
    # pastas de jogos configuradas num shadPS4 com interface que a pessoa já tenha usado (%APPDATA%\shadPS4)
    $dirs = @()
    $toml = Join-Path $env:APPDATA 'shadPS4\config.toml'
    if (Test-Path -LiteralPath $toml) {
        $line = Select-String -LiteralPath $toml -Pattern '^\s*installDirs\s*=\s*\[(.*)\]' | Select-Object -First 1
        if ($line) { $dirs = @([regex]::Matches($line.Matches[0].Groups[1].Value, '"((?:[^"\\]|\\.)*)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }) }
    }
    return $dirs
}

# ---------------------------------------------------------------- instalar PKG de PS4 direto pelo launcher
# PkgTool (LibOrbisPkg, LGPL-3.0) extrai os arquivos do jogo (pasta uroot do PKG); os arquivos de sce_sys
# (param.sfo, ícone, troféus...) são entradas separadas do PKG e saem uma a uma, como o shadPS4 faz.
# Jogo: <pasta de jogos>\CUSAxxxxx. Update: CUSAxxxxx-UPDATE ao lado do jogo (o shadPS4 usa sozinho).
# O PkgTool mapeia o PKG inteiro na memória e extrai com várias threads: num PKG de 30 GB isso enche a RAM
# e trava o PC. Aqui a memória física dele tem limite (o que passar vira cache que o Windows libera quando
# precisar), mas o processador e o disco ficam livres para ele, o mais rápido possível.
# O progresso vem dos bytes que ele já gravou.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PL {
    public static class ProcLimit {
        [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSizeEx(IntPtr h, IntPtr min, IntPtr max, int flags);
        [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
        [DllImport("kernel32.dll")] static extern bool GetProcessIoCounters(IntPtr h, out IoCounters c);
        public static void Limit(IntPtr h, long maxBytes) {
            // 0x4 = teto rígido do working set; 0x2 = sem mínimo rígido
            try { SetProcessWorkingSetSizeEx(h, (IntPtr)(16L << 20), (IntPtr)maxBytes, 0x4 | 0x2); } catch { }
        }
        [DllImport("kernel32.dll")] static extern bool SetProcessWorkingSetSize(IntPtr h, IntPtr min, IntPtr max);
        // o teto acima nem sempre pega (páginas do arquivo mapeado): esvaziar devolve tudo ao cache do Windows
        public static void Trim(IntPtr h) { try { SetProcessWorkingSetSize(h, (IntPtr)(-1), (IntPtr)(-1)); } catch { } }
        public static long Written(IntPtr h) {
            IoCounters c;
            try { if (GetProcessIoCounters(h, out c)) return (long)c.WriteBytes; } catch { }
            return -1;
        }
    }
}
'@

$PkgSkipEntries = @('DIGESTS', 'ENTRY_KEYS', 'IMAGE_KEY', 'GENERAL_DIGESTS', 'METAS', 'ENTRY_NAMES', 'LICENSE_DAT', 'LICENSE_INFO', 'PUBTOOLINFO_DAT')

function Get-PkgToolExe {
    $e = Join-Path $EmuRoot 'pkgtool\PkgTool.exe'
    if (Test-Path -LiteralPath $e) { return $e }
    return $null
}

function Get-PkgEntryFileName([string]$entry) {
    # nome da entrada -> arquivo em sce_sys: PARAM_SFO -> param.sfo, TROPHY__TROPHY00_TRP -> trophy/trophy00.trp
    $n = $entry.ToLower()
    if ($n -match '^changeinfo__changeinfo(_\d+)?_xml$') { return "changeinfo/changeinfo$($Matches[1]).xml" }
    $n = $n -replace '__', '/'
    $i = $n.LastIndexOf('_')
    if ($i -gt 0) { $n = $n.Substring(0, $i) + '.' + $n.Substring($i + 1) }
    return ($n -replace '_', '-')
}

function Invoke-PkgTool([string[]]$a) {
    # comandos rápidos (lista de entradas, uma entrada): espera terminar
    try { $o = & (Get-PkgToolExe) @a 2>&1 } catch { return @{ code = -1; out = @("$($_.Exception.Message)") } }
    return @{ code = $LASTEXITCODE; out = @($o | ForEach-Object { "$_" }) }
}

function Write-AppLog([string]$msg) {
    # vai para cache\erros.log, que aparece no Diagnóstico (Sobre > Diagnóstico > Copiar) para pedir ajuda
    try {
        $f = Join-Path $Root 'cache\erros.log'
        New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
        [IO.File]::AppendAllText($f, "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] $msg`r`n", (New-Object Text.UTF8Encoding($false)))
    } catch {}
}

function Get-PkgToolError([string[]]$out) {
    # PkgTool mostra o erro como exceção do .NET: "Unhandled Exception: System.Exception: Invalid CNT header"
    $l = @($out | Where-Object { $_ -match 'Exception:' } | Select-Object -First 1)
    if ($l) { return (($l[0] -replace '^.*?(System\.)?\w*Exception:\s*', '').Trim()) }
    return (@($out | Where-Object { $_.Trim() }) | Select-Object -First 2) -join ' '
}

function Get-PkgErrorText([string]$err) {
    # o erro do PkgTool em palavras
    if ($err -match 'CNT header|magic') { return (L 'Este arquivo não é um PKG de PS4 (ou está incompleto/corrompido). Baixe de novo.') }
    if ($err -match '(?i)decrypt|crypt|EKPFS|passcode') { return (L 'Este PKG é criptografado (PKG oficial da PSN). O launcher só instala PKG desbloqueado (fPKG), o mesmo que o shadPS4 aceita.') }
    if ($err -match '(?i)space|espa[cç]o') { return (L 'Falta espaço no disco.') }
    if ($err -match '(?i)access|acesso|denied|negado|being used|sendo usado') { return (L 'O Windows não deixou ler ou gravar os arquivos (pasta protegida, antivírus ou arquivo aberto em outro programa). Tente outra pasta de instalação.') }
    return (L 'O PkgTool não conseguiu ler este PKG.')
}

function Test-PkgToolRuns {
    # abre o PkgTool sem nada (ele só mostra a ajuda): se nem isso funciona, o Windows ou o antivírus bloqueou
    $r = Invoke-PkgTool @()
    if (@($r.out | Where-Object { $_ -match 'Usage' }).Count) { return $null }
    return "código $($r.code): $(Get-PkgToolError $r.out)"
}

function Get-PkgEntries([string]$pkg) {
    $r = Invoke-PkgTool @('pkg_listentries', $pkg)
    $list = @()
    foreach ($l in $r.out) { if ($l -match '^0x[0-9A-F]+\s+0x[0-9A-F]+\s+\w+\s+(\d+)\s+(?:\d+\s+)?(\S+)\s*$') { $list += @{ index = [int]$Matches[1]; name = $Matches[2] } } }
    return $list
}

function Install-Ps4Pkg([string]$pkg, $g = $null) {
    # $g: entrada "PS4 (PKG)" da biblioteca, que vira o jogo instalado quando terminar
    if ($script:PkgJob) { Show-Toast 'Já tem um PKG sendo instalado' 'warn'; return }
    if (-not (Get-PkgToolExe)) {
        $r = [PL.Lang]::Msg("Para instalar PKG direto pelo launcher falta o PkgTool.`nInstalar agora? (Emuladores > Instalar / atualizar todos)", 'Instalar PKG de PS4', 'YesNo')
        if ($r -eq 'Yes') { Show-EmulatorsDialog }
        if (-not (Get-PkgToolExe)) { return }
    }
    $blocked = Test-PkgToolRuns
    if ($blocked) {
        Write-AppLog "PKG: o PkgTool não abriu ($blocked) - $(Get-PkgToolExe)"
        [void][PL.Lang]::Msg("O PkgTool (programa que instala o PKG) não abriu neste PC.`n`nNormalmente é o antivírus que colocou o PkgTool em quarentena, ou a pasta do Trivium Hub ficou incompleta ao extrair o zip. Confira o histórico do antivírus, ou extraia o zip de novo (com o 7-Zip ou o WinRAR) numa pasta como Documentos.`n`nDetalhe: $blocked", 'Instalar PKG de PS4')
        return
    }
    # o PkgTool precisa do arquivo só para ele (programa de torrent compartilhando o PKG atrapalha)
    try { ([IO.File]::Open($pkg, 'Open', 'Read', 'None')).Dispose() } catch {
        [void][PL.Lang]::Msg("O arquivo está aberto em outro programa (por exemplo o qBittorrent compartilhando).`nPause ou remova o torrent e tente de novo.`n`n$pkg", 'Instalar PKG de PS4')
        return
    }
    $form.Cursor = 'WaitCursor'
    $entries = @(Get-PkgEntries $pkg)
    $sfoEntry = $entries | Where-Object { $_.name -eq 'PARAM_SFO' } | Select-Object -First 1
    $tmp = Join-Path $env:TEMP 'TriviumHub-pkg'
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $sfo = Join-Path $tmp 'param.sfo'
    Remove-Item -LiteralPath $sfo -ErrorAction SilentlyContinue
    $sfoRun = $null
    if ($sfoEntry) { $sfoRun = Invoke-PkgTool @('pkg_extractentry', $pkg, [string]$sfoEntry.index, $sfo) }
    $form.Cursor = 'Default'
    if (-not (Test-Path -LiteralPath $sfo)) {
        # erro de verdade do PkgTool (lista de entradas ou a extração do param.sfo)
        $err = if ($sfoRun) { Get-PkgToolError $sfoRun.out } else { Get-PkgToolError (Invoke-PkgTool @('pkg_listentries', $pkg)).out }
        Write-AppLog "PKG: não leu $pkg - $err"
        [void][PL.Lang]::Msg("Não deu para ler este PKG.`n`n$(Get-PkgErrorText $err)`n`nArquivo: $pkg`nDetalhe: $err", 'Instalar PKG de PS4')
        return
    }
    $tid = Read-SfoField $sfo 'TITLE_ID'; $cat = Read-SfoField $sfo 'CATEGORY'; $title = Read-SfoField $sfo 'TITLE'; $ver = Read-SfoField $sfo 'APP_VER'
    if ($cat -like 'ac*') { [void][PL.Lang]::Msg("Este PKG é uma DLC ($title). Por enquanto o launcher instala só jogos e updates.", 'Instalar PKG de PS4'); return }

    # onde instalar: update vai ao lado do jogo que já está na biblioteca
    $isPatch = $cat -eq 'gp'
    $base = $null
    # ($baseGame: $bg é a cor de fundo do tema e as janelas abertas daqui a usariam)
    foreach ($baseGame in $script:Cfg.games) { if ($baseGame.console -eq 'PS4' -and (Split-Path $baseGame.path -Leaf) -eq $tid) { $base = $baseGame; break } }
    if ($isPatch -and $base) { $dest = "$($base.path)-UPDATE" }
    else {
        $root = [string]$script:Cfg.ps4InstallDir
        if (-not $root -or -not (Test-Path -LiteralPath $root)) {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = L 'Escolha a pasta onde os jogos de PS4 serão instalados (precisa de espaço livre do tamanho do PKG)'
            $first = @(Get-Ps4PkgInstallDirs) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            $dlg.SelectedPath = if ($first) { $first } else { Split-Path $pkg }
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $root = $dlg.SelectedPath; $script:Cfg.ps4InstallDir = $root; Save-Config
        }
        $dest = Join-Path $root $(if ($isPatch) { "$tid-UPDATE" } else { $tid })
    }
    if (-not $isPatch -and (Get-Ps4Game $dest)) {
        # já instalado: só coloca na biblioteca
        Complete-Ps4PkgInstall $dest $g $false $title $ver
        return
    }
    $size = (Get-Item -LiteralPath $pkg).Length
    $free = (Get-PSDrive ((Split-Path $dest -Qualifier).TrimEnd(':'))).Free
    if ($free -lt $size * 1.05) {
        [void][PL.Lang]::Msg(("Falta espaço em {0}: o PKG tem {1:N1} GB e há {2:N1} GB livres." -f (Split-Path $dest -Qualifier), ($size / 1GB), ($free / 1GB)), 'Instalar PKG de PS4')
        return
    }
    # PKG grande: pede para fechar o resto (memória e disco livres deixam a instalação bem mais rápida)
    if ($size -gt 1GB) {
        $min = [math]::Max(1, [math]::Ceiling($size / 1GB / 3))   # ~3 GB por minuto num SSD; HD é mais lento
        $r = [PL.Lang]::Msg(("Antes de instalar, feche os outros programas (jogos, navegador, Discord, torrent...) e deixe só o Trivium Hub aberto.`n`nAssim a instalação usa toda a memória e o disco do PC e termina mais rápido.`nTamanho: {0:N1} GB  ·  tempo estimado: cerca de {1} min (num HD pode levar mais).`n`nNão feche o Trivium Hub até terminar. Começar a instalação?" -f ($size / 1GB), $min), 'Instalar PKG de PS4', 'YesNo', 'Information')
        if ($r -ne 'Yes') { return }
    }
    $part = "$dest.instalando"
    if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Recurse -Force }
    $log = Join-Path $tmp 'pkgtool.log'
    try {
        $p = Start-Process -FilePath (Get-PkgToolExe) -ArgumentList "pkg_extract `"$pkg`" `"$part`"" -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err" -ErrorAction Stop
    } catch {
        Write-AppLog "PKG: o PkgTool não abriu - $($_.Exception.Message)"
        [void][PL.Lang]::Msg("O PkgTool não abriu: $($_.Exception.Message)`n`nConfira se o antivírus não bloqueou o PkgTool.", 'Instalar PKG de PS4')
        return
    }
    [void]$p.Handle   # sem segurar o handle, o ExitCode volta vazio depois que o processo termina
    # o mais rápido possível: prioridade acima do normal (a pessoa foi avisada para fechar o resto)
    try { $p.PriorityClass = 'AboveNormal' } catch {}
    # memória física: no máximo 1/4 da RAM (entre 1 e 3 GB)
    $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $ramCap = [long][math]::Max([long]1GB, [math]::Min([long]3GB, [long]($ram / 4)))
    [PL.ProcLimit]::Limit($p.Handle, $ramCap)
    $script:PkgJob = @{ proc = $p; ramCap = $ramCap; pkg = $pkg; dest = $dest; part = $part; size = $size; g = $g; patch = $isPatch; title = $title; ver = $ver; tid = $tid; entries = $entries; start = Get-Date }
    Show-PkgProgress
    $pkgTimer.Start()
}

function Show-PkgProgress {
    $j = $script:PkgJob
    $d = New-Dialog 'Instalando PKG de PS4' 520 190
    $d.ControlBox = $false
    $t = New-Label "$($j.title)" 20 16; $t.Font = $fontBold; $t.MaximumSize = New-Object System.Drawing.Size(480, 0)
    $k = if ($j.patch) { "Update $($j.ver)" } else { "Jogo, versão $($j.ver)" }
    $s = New-Label "$k  ·  $($j.tid)  ·  $('{0:N1}' -f ($j.size / 1GB)) GB" 20 42 $dim
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Left = 20; $bar.Top = 78; $bar.Width = 480; $bar.Height = 10; $bar.BackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
    $fill = New-Object System.Windows.Forms.Panel
    $fill.Left = 0; $fill.Top = 0; $fill.Height = 10; $fill.Width = 0; $fill.BackColor = $accent
    $bar.Controls.Add($fill)
    $st = New-Label 'Começando...' 20 98 $dim
    $bCancel = New-Button 'Cancelar' 380 138 120 36
    $bCancel.Add_Click({ Stop-PkgInstall $true })
    $d.Controls.AddRange(@($t, $s, $bar, $st, $bCancel))
    $j.dlg = $d; $j.fill = $fill; $j.status = $st
    $d.Show($form)
}

function Stop-PkgInstall([bool]$cancel) {
    $j = $script:PkgJob
    if (-not $j) { return }
    $pkgTimer.Stop()
    if ($cancel) {
        try { if (-not $j.proc.HasExited) { $j.proc.Kill(); $j.proc.WaitForExit(5000) } } catch {}
        Remove-Item -LiteralPath $j.part -Recurse -Force -ErrorAction SilentlyContinue
        Show-Toast 'Instalação do PKG cancelada' 'info'
    }
    if ($j.dlg) { $j.dlg.Close(); $j.dlg.Dispose() }
    $script:PkgJob = $null
}

function Get-DirSize([string]$dir) {
    $n = 0L
    try { foreach ($f in [IO.Directory]::EnumerateFiles($dir, '*', 'AllDirectories')) { $n += (New-Object IO.FileInfo($f)).Length } } catch {}
    return $n
}

$pkgTimer = New-Object System.Windows.Forms.Timer
$pkgTimer.Interval = 1000
$pkgTimer.Add_Tick({
        $j = $script:PkgJob
        if (-not $j) { $pkgTimer.Stop(); return }
        if (-not $j.proc.HasExited) {
            # progresso: bytes que o PkgTool já gravou (o jogo descompactado tem quase o tamanho do PKG);
            # somar os arquivos da pasta não serve: o Windows só atualiza o tamanho quando o arquivo fecha
            $done = [PL.ProcLimit]::Written($j.proc.Handle)
            if ($done -lt 0) { $done = 0 }
            # memória: passou do limite, esvazia (sem isso um PKG de 30 GB toma a RAM toda e trava o PC)
            try { $j.proc.Refresh(); if ($j.proc.WorkingSet64 -gt $j.ramCap) { [PL.ProcLimit]::Trim($j.proc.Handle) } } catch {}
            # ([long]1: com 1 o PowerShell escolhe a conta em Int32 e quebra com PKG de mais de 2 GB)
            $pct = [math]::Min(98, [int](100.0 * $done / [math]::Max([long]1, [long]$j.size)))
            $j.fill.Width = [int](480 * $pct / 100)
            # velocidade (GB por minuto) e tempo que falta, pelos últimos ~10 segundos (fica estável e acompanha o disco)
            $now = Get-Date
            if (-not $j.samples) { $j.samples = New-Object System.Collections.ArrayList }
            [void]$j.samples.Add(@($now, $done))
            while ($j.samples.Count -gt 11) { $j.samples.RemoveAt(0) }
            $info = ''
            $first = $j.samples[0]
            $dt = ($now - $first[0]).TotalSeconds
            if ($dt -ge 4 -and $done -gt $first[1]) {
                $bps = ($done - $first[1]) / $dt
                $left = [int]([math]::Max([double]0, [double]($j.size - $done)) / $bps)
                $tl = if ($left -ge 60) { "faltam ~$([math]::Ceiling($left / 60)) min" } else { "faltam ~$left s" }
                $info = "  ·  {0:N1} GB/min  ·  {1}" -f ($bps * 60 / 1GB), $tl
            }
            $j.status.Text = (L "Extraindo... $pct%") + $info + ("  ·  {0:N1} de {1:N1} GB" -f ($done / 1GB), ($j.size / 1GB))
            return
        }
        $pkgTimer.Stop()
        $code = $j.proc.ExitCode
        if ($null -eq $code) { $code = 0 }   # sem código: vale o que foi extraído (eboot.bin conferido abaixo)
        $uroot = Join-Path $j.part 'uroot'
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $uroot 'eboot.bin'))) {
            $tmpLog = Join-Path $env:TEMP 'TriviumHub-pkg\pkgtool.log'
            $out = @(Get-Content -LiteralPath "$tmpLog.err" -ErrorAction SilentlyContinue) + @(Get-Content -LiteralPath $tmpLog -Tail 5 -ErrorAction SilentlyContinue)
            $err = Get-PkgToolError $out
            if (-not $err) { $err = L "o PkgTool terminou com o código $code sem extrair o jogo" }
            Write-AppLog "PKG: falhou ao extrair $($j.pkg) (código $code) - $err"
            Remove-Item -LiteralPath $j.part -Recurse -Force -ErrorAction SilentlyContinue
            Stop-PkgInstall $false
            [void][PL.Lang]::Msg("Não deu para instalar o PKG.`n`n$(Get-PkgErrorText $err)`n`nDetalhe: $err", 'Instalar PKG de PS4')
            return
        }
        $j.status.Text = L 'Copiando ícone, troféus e informações do jogo...'; $j.fill.Width = 470; $j.dlg.Refresh()
        # arquivos de sce_sys que ficam fora da imagem do jogo, como entradas do PKG
        $sys = Join-Path $uroot 'sce_sys'
        New-Item -ItemType Directory -Force $sys | Out-Null
        foreach ($en in $j.entries) {
            if ($en.name -in $PkgSkipEntries) { continue }
            $file = Join-Path $sys ((Get-PkgEntryFileName $en.name).Replace('/', '\'))
            New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
            [void](Invoke-PkgTool @('pkg_extractentry', $j.pkg, [string]$en.index, $file))
        }
        # update por cima de um anterior: troca a pasta inteira
        if (Test-Path -LiteralPath $j.dest) { Remove-Item -LiteralPath $j.dest -Recurse -Force }
        Move-Item -LiteralPath $uroot $j.dest
        Remove-Item -LiteralPath $j.part -Recurse -Force -ErrorAction SilentlyContinue
        $jj = $j
        Stop-PkgInstall $false
        Complete-Ps4PkgInstall $jj.dest $jj.g $jj.patch $jj.title $jj.ver
    })

function Complete-Ps4PkgInstall([string]$dest, $g, [bool]$patch, [string]$title, [string]$ver) {
    if ($patch) {
        Show-Toast "Update $ver instalado: $title" 'ok'
        Set-Status "Update $ver instalado em $dest"
        if ($g) { $script:Cfg.games = @($script:Cfg.games | Where-Object { $_.path -ne $g.path }); Save-Config }
        Refresh-List
        return
    }
    $game = Get-Ps4Game $dest
    if ($g) { $g.console = 'PS4'; $g.path = $dest; $g.name = $game.name }
    elseif (-not @($script:Cfg.games | Where-Object { $_.path -eq $dest }).Count) {
        $new = New-Game $game.name 'PS4' $dest
        $new | Add-Member -NotePropertyName added -NotePropertyValue ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -Force
        $script:Cfg.games = @($script:Cfg.games) + $new
        $g = $new
    }
    Save-Config; Refresh-List
    if ($g) { [void](Select-Game $g) }
    Show-Toast "Instalado: $($game.name)" 'ok'
    Set-Status "PKG instalado em $dest"
}

function Invoke-InstallPkgDialog {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = L 'Escolha o PKG de PS4 (jogo ou update) ou o eboot.bin de um jogo já instalado'
    # jogo já instalado (pasta com eboot.bin): não precisa instalar, só entra na biblioteca
    $dlg.Filter = L 'PKG de PS4 ou jogo instalado|*.pkg;eboot.bin|Todos|*.*'
    $root = [string]$script:Cfg.ps4InstallDir
    if ($root -and (Test-Path -LiteralPath $root)) { $dlg.InitialDirectory = $root }
    if ($dlg.ShowDialog() -ne 'OK') { return }
    if ([IO.Path]::GetFileName($dlg.FileName) -ieq 'eboot.bin') { Add-Games @($dlg.FileName); return }
    Install-Ps4Pkg $dlg.FileName
}

function Start-Ps4Pkg($g, $s) {
    # PKG de PS4: o launcher instala (PkgTool); depois de instalado, a entrada vira a pasta do jogo
    $tid = Get-Ps4PkgTitleId $g.path
    foreach ($d in @(Get-Ps4PkgInstallDirs) + @([string]$script:Cfg.ps4InstallDir | Where-Object { $_ }) + (Split-Path $g.path)) {
        $dir = Join-Path $d $tid
        $game = Get-Ps4Game $dir
        if (-not $game) { continue }
        $g.console = 'PS4'; $g.path = $dir; $g.name = $game.name
        Save-Config; Refresh-List
        Start-Ps4Game $g $s
        return
    }
    # não instalado: o launcher instala sozinho (sem o PkgTool, Install-Ps4Pkg oferece instalar)
    Install-Ps4Pkg $g.path $g
}

function Start-Ps4Game($g, $s) {
    $port = Get-NativePort $g
    if ($port) {
        $exe = $script:Cfg[$port.key]
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
            $r = [PL.Lang]::Msg(
                "$($port.game) roda muito melhor no $($port.name) (port nativo, sem emular a CPU).`nInstalar o $($port.name) agora?`n(Não = usar o shadPS4)",
                'Trivium Hub', 'YesNoCancel')
            if ($r -eq 'Cancel') { return }
            if ($r -eq 'Yes') { Show-EmulatorsDialog; $exe = $script:Cfg[$port.key] }
        }
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            $dir = Split-Path $exe
            $play = Join-Path $dir $port.play
            Enable-PerfPowerPlan $s
            if ((Test-PortConfigured $port $dir $g.path) -and (Test-Path -LiteralPath $play)) {
                Start-Emu $play @() 'game' $s
                Set-Status "Jogando (PS4 / $($port.name)): $($g.name)"
            } else {
                Open-PortSetup $port $g
            }
            return
        }
    }

    $exe = Require-Emu 'shadps4'
    if (-not $exe) { return }
    Apply-Shadps4Settings $exe (Get-Ps4TitleId $g.path) $s
    if ($s.showFps) { Set-Shadps4FpsCorner (Join-Path (Split-Path $exe) 'user') ([bool]$s.fullscreen) }
    if ($s.communityFix -and (Get-PatchVersionWarning $g)) { Show-Toast 'Os patches deste jogo são para outra versão: veja em Configurar' 'warn' }
    # shadPS4 eltutz (cuesta4): fica na mesma pasta do oficial e usa a mesma pasta user (saves, shaders, patches)
    if ($s.eltutz -and -not $s.officialEmu) {
        $el = Join-Path (Split-Path $exe) 'shadps4-eltutz.exe'
        if (-not [PL.Cpu]::HasAvx2()) { Show-Toast 'Seu processador não tem AVX2: usando o shadPS4 oficial' 'warn' }
        elseif (Test-Path -LiteralPath $el) { $exe = $el }
        else { Show-Toast 'shadPS4 eltutz não instalado: Emuladores > Instalar / atualizar todos' 'warn' }
    }
    Initialize-Shadps4Users $exe
    # em tela cheia direta a placa mostra o emulador por cima de tudo, com a tela "Loading game" dele. Abre em janela,
    # atrás da animação, e Release-LaunchOverlay cobre o monitor quando o jogo estiver pronto
    $script:OvExpand = [bool]$s.fullscreen -and $script:PlayFxOk
    $a = @('--fullscreen', ([bool]$s.fullscreen -and -not $script:OvExpand).ToString().ToLower())
    if ($s.showFps) { $a += '--show-fps' }
    $a += '-g', "`"$(Join-Path $g.path 'eboot.bin')`""
    Enable-PerfPowerPlan $s
    try { Initialize-Ps4Memory $s } catch { Write-AppLog "Memória virtual: $($_.Exception.Message)" }
    try { Write-Ps4TrophyFiles $exe $g } catch { Write-AppLog "Troféus do PS4: $($_.Exception.Message)" }
    Start-Ps4TrophyWatch $exe $g ([bool]$s.trophyPopup)
    Start-Emu $exe $a 'game' $s
    $emuName = 'shadPS4'; if ((Split-Path $exe -Leaf) -eq 'shadps4-eltutz.exe') { $emuName = 'shadPS4 eltutz' }
    Set-Status "Jogando (PS4 / $emuName): $($g.name)"
}

function Start-Game($g) {
    if ($script:RunDir) { Show-Toast 'Já existe um jogo ou emulador aberto' 'warn'; return }
    if (-not (Test-Path -LiteralPath $g.path)) {
        [void][PL.Lang]::Msg("Arquivo não encontrado:`n$($g.path)", 'Trivium Hub')
        return
    }
    $s = Get-GameSettings $g
    $s.nvVibrance = ($g.console -ne 'PS2')   # PS2 usa o Shade Boost do PCSX2
    $script:RunGame = $g

    if ($g.console -eq 'PS4 (PKG)') { Start-Ps4Pkg $g $s; return }
    if ($g.console -eq 'PS4') { Start-Ps4Game $g $s; return }

    if ($g.console -eq 'PS2') {
        $exe = Require-Emu 'pcsx2'
        if (-not $exe) { return }
        if (-not (Test-Pcsx2Ready $exe)) {
            if (-not (Show-Ps2BiosDialog)) { Set-Status 'Escolha a BIOS do PS2 para jogar.'; return }
        }
        Repair-Ps2FileName $g
        # patch de 60 FPS da comunidade, se o jogo tiver; alguns pedem a CPU do PS2 mais rápida
        $fp = Get-Ps2FpsPatch $g $exe
        if ($fp) {
            Set-Ps2FpsPatch $exe $fp ([bool]$s.fps60)
            if ($s.fps60 -and [int]$s.eeCycle -lt $fp.ee) { $s.eeCycle = $fp.ee }
        }
        [void](Apply-Pcsx2Settings $exe $s)
        $a = @()
        if ($s.fullscreen) { $a += '-fullscreen' }
        # na última vez o jogo não fechou normalmente: oferece continuar do save automático
        $auto = $null
        if ($g.running) { $auto = Get-Pcsx2AutoState $exe $g }
        if ($auto) {
            $r = [PL.Lang]::Msg(
                "Na última vez o jogo fechou de forma inesperada.`n`nContinuar do save automático de $($auto.LastWriteTime.ToString('dd/MM HH:mm'))?`n(Não = começar normalmente)",
                $g.name, 'YesNoCancel', 'Question')
            if ($r -eq 'Cancel') { return }
            if ($r -eq 'Yes') { $a += '-statefile', "`"$($auto.FullName)`"" }
        }
        $a += '-nogui', '-batch', '--', "`"$($g.path)`""
        Enable-PerfPowerPlan $s
        Set-GameRunningFlag $g $true
        Start-Emu $exe $a 'game' $s
        $script:AutoSaveExe = $exe
        if ([int]$s.autosave -gt 0) { $autoTimer.Interval = [int]$s.autosave * 60000; $autoTimer.Start() }
        Set-Status "Jogando (PS2): $($g.name)"
        return
    }

    $exe = Require-Emu 'rpcs3'
    if (-not $exe) { return }
    if (-not (Test-Path (Join-Path (Split-Path $exe) 'dev_flash\vsh\module\vsh.self'))) {
        [void][PL.Lang]::Msg(
            "O firmware do PS3 ainda não está instalado no RPCS3.`nVá em Emuladores > Firmware do PS3.", 'Trivium Hub')
        Show-EmulatorsDialog
        return
    }
    $target = $g.path

    if ($g.console -eq 'PS3 (PKG)') {
        $tid = Get-PkgTitleId $g.path
        $eboot = Join-Path (Split-Path $exe) "dev_hdd0\game\$tid\USRDIR\EBOOT.BIN"
        if (-not (Test-Path $eboot)) {
            $r = [PL.Lang]::Msg(
                "O PKG ($tid) ainda não está instalado no RPCS3.`nInstalar agora? Depois de instalar, feche o RPCS3 e clique em JOGAR de novo.",
                'Trivium Hub', 'YesNo')
            if ($r -ne 'Yes') { return }
            Start-Emu $exe @('--installpkg', "`"$($g.path)`"") 'setup' $s
            Set-Status "Instalando PKG $tid no RPCS3..."
            return
        }
        $target = $eboot
    }

    $pad = Set-Rpcs3Controller $exe
    if (-not (Apply-Rpcs3Settings $exe (Get-Ps3TitleId $g) $s)) {
        Set-Status 'Aviso: ISO de PS3 usa a configuração global do RPCS3 (as opções do jogo valem para pastas e PKG).'
    }
    Enable-PerfPowerPlan $s
    Start-Emu $exe @('--no-gui', "`"$target`"") 'game' $s
    Set-Status "Jogando (PS3): $($g.name)  -  controle: $pad"
}

# ---------------------------------------------------------------- interface: tema

$bg = [System.Drawing.Color]::FromArgb(24, 24, 28)
$panelBg = [System.Drawing.Color]::FromArgb(34, 34, 40)
$fg = [System.Drawing.Color]::FromArgb(235, 235, 240)
$dim = [System.Drawing.Color]::FromArgb(160, 160, 175)
$accent = [System.Drawing.Color]::FromArgb(70, 110, 230)
$okColor = [System.Drawing.Color]::FromArgb(110, 220, 140)
$badColor = [System.Drawing.Color]::FromArgb(255, 140, 120)
$consoleColors = @{
    'PS2'       = [System.Drawing.Color]::FromArgb(120, 170, 255)
    'PS3'       = [System.Drawing.Color]::FromArgb(255, 130, 130)
    'PS3 (PKG)' = [System.Drawing.Color]::FromArgb(255, 130, 130)
    'PS4'       = [System.Drawing.Color]::FromArgb(110, 220, 170)
    'PS4 (PKG)' = [System.Drawing.Color]::FromArgb(110, 220, 170)
}
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$fontBold = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)

# visual da tela de configurações (cartões e botões deslizantes). Separado: se falhar, ela usa caixas de marcar comuns
$script:UiKitOk = $false
try {
    Add-Type -ErrorAction Stop -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace PL {
    public class SetCard : Panel {
        public SetCard() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
        protected override void OnPaintBackground(PaintEventArgs e) {
            e.Graphics.Clear(Parent != null ? Parent.BackColor : BackColor);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var p = UiKit.Round(new RectangleF(0, 0, Width - 1, Height - 1), 12))
            using (var br = new SolidBrush(BackColor))
            using (var pen = new Pen(Color.FromArgb(52, 52, 62))) { e.Graphics.FillPath(br, p); e.Graphics.DrawPath(pen, p); }
        }
    }

    // caixa de marcar com cara de botão deslizante; continua sendo CheckBox para o resto do launcher
    public class Toggle : CheckBox {
        public Color Accent = Color.FromArgb(70, 110, 230);
        readonly Timer anim = new Timer { Interval = 15 };
        float pos;
        bool over;
        public Toggle() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            AutoSize = false; Cursor = Cursors.Hand;
            anim.Tick += delegate {
                float goal = Checked ? 1f : 0f;
                pos += (goal - pos) * .34f;
                if (Math.Abs(goal - pos) < .02f) { pos = goal; anim.Stop(); }
                Invalidate();
            };
        }
        protected override void OnCheckedChanged(EventArgs e) {
            base.OnCheckedChanged(e);
            if (IsHandleCreated && Visible) anim.Start(); else { pos = Checked ? 1f : 0f; Invalidate(); }
        }
        protected override void OnMouseEnter(EventArgs e) { over = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { over = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e) {
            var g = e.Graphics;
            g.Clear(Parent != null ? Parent.BackColor : BackColor);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (over && Enabled) using (var p = UiKit.Round(new RectangleF(0, 0, Width - 1, Height - 1), 7))
                using (var br = new SolidBrush(Color.FromArgb(14, 255, 255, 255))) g.FillPath(br, p);
            int tw = 42, th = 22, tx = Width - tw - 6, ty = (Height - th) / 2;
            var text = new Rectangle(4, 0, tx - 12, Height);
            TextRenderer.DrawText(g, Text, Font, text, Enabled ? ForeColor : Color.FromArgb(120, 120, 132),
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            Color off = Color.FromArgb(70, 70, 82), on = Enabled ? Accent : Color.FromArgb(70, 80, 112);
            using (var p = UiKit.Round(new RectangleF(tx, ty, tw, th), th / 2f))
            using (var br = new SolidBrush(Mix(off, on, pos))) g.FillPath(br, p);
            float d = th - 6, kx = tx + 3 + (tw - d - 6) * pos;
            using (var br = new SolidBrush(Enabled ? Color.White : Color.FromArgb(170, 170, 180))) g.FillEllipse(br, kx, ty + 3, d, d);
            if (Focused && ShowFocusCues) using (var pen = new Pen(Color.FromArgb(120, 255, 255, 255))) g.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
        }
        static Color Mix(Color a, Color b, float k) { return Color.FromArgb((int)(a.R + (b.R - a.R) * k), (int)(a.G + (b.G - a.G) * k), (int)(a.B + (b.B - a.B) * k)); }
        protected override void Dispose(bool disposing) { if (disposing) anim.Dispose(); base.Dispose(disposing); }
    }

    // abas à esquerda, com um marcador que desliza até a aba escolhida
    public class SetNav : Control {
        public readonly System.Collections.Generic.List<string> Items = new System.Collections.Generic.List<string>();
        public Color Accent = Color.FromArgb(70, 110, 230);
        public event EventHandler SelectedChanged;
        const int RowH = 44, Top0 = 12;
        readonly Timer anim = new Timer { Interval = 12 };
        int sel, hover = -1;
        float barY = Top0;
        public int SelectedIndex {
            get { return sel; }
            set {
                if (value < 0 || value >= Items.Count || value == sel) return;
                sel = value; anim.Start(); Invalidate();
                if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty);
            }
        }
        public SetNav() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            Cursor = Cursors.Hand; TabStop = true;
            anim.Tick += delegate {
                float goal = Top0 + sel * RowH;
                barY += (goal - barY) * .3f;
                if (Math.Abs(goal - barY) < .6f) { barY = goal; anim.Stop(); }
                Invalidate();
            };
        }
        int RowAt(int y) { int i = (y - Top0) / RowH; return y >= Top0 && i < Items.Count ? i : -1; }
        protected override void OnMouseMove(MouseEventArgs e) { int i = RowAt(e.Y); if (i != hover) { hover = i; Invalidate(); } base.OnMouseMove(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = -1; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { int i = RowAt(e.Y); if (i >= 0) SelectedIndex = i; base.OnMouseDown(e); }
        protected override bool IsInputKey(Keys k) { return k == Keys.Up || k == Keys.Down || base.IsInputKey(k); }
        protected override void OnKeyDown(KeyEventArgs e) {
            if (e.KeyCode == Keys.Up) SelectedIndex = sel - 1; else if (e.KeyCode == Keys.Down) SelectedIndex = sel + 1;
            base.OnKeyDown(e);
        }
        protected override void OnPaint(PaintEventArgs e) {
            var g = e.Graphics;
            g.Clear(BackColor); g.SmoothingMode = SmoothingMode.AntiAlias;
            if (hover >= 0 && hover != sel) using (var p = UiKit.Round(new RectangleF(8, Top0 + hover * RowH + 2, Width - 16, RowH - 4), 8))
                using (var br = new SolidBrush(Color.FromArgb(16, 255, 255, 255))) g.FillPath(br, p);
            using (var p = UiKit.Round(new RectangleF(8, barY + 2, Width - 16, RowH - 4), 8))
            using (var br = new SolidBrush(Color.FromArgb(66, Accent))) g.FillPath(br, p);
            using (var p = UiKit.Round(new RectangleF(10, barY + 12, 4, RowH - 24), 2))
            using (var br = new SolidBrush(Accent)) g.FillPath(br, p);
            for (int i = 0; i < Items.Count; i++)
                TextRenderer.DrawText(g, Items[i], Font, new Rectangle(24, Top0 + i * RowH, Width - 30, RowH), i == sel ? Color.White : Color.FromArgb(175, 175, 190),
                    TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
        }
        protected override void Dispose(bool disposing) { if (disposing) anim.Dispose(); base.Dispose(disposing); }
    }

    public static class UiKit {
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr h, string app, string list);
        // desenho sem piscar ao mover o painel
        public static void Smooth(Control c) {
            var p = typeof(Control).GetProperty("DoubleBuffered", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
            if (p != null) p.SetValue(c, true, null);
        }
        // a aba nova entra deslizando até a posição dela
        public static void SlideIn(Control c, int from) {
            var clock = System.Diagnostics.Stopwatch.StartNew();
            var t = new Timer { Interval = 10 };
            c.Left = from;
            t.Tick += delegate {
                double k = Math.Min(1.0, clock.ElapsedMilliseconds / 190.0), u = 1 - k;
                if (c.IsDisposed) { t.Stop(); t.Dispose(); return; }
                c.Left = (int)Math.Round(from * u * u * u);
                if (k >= 1) { t.Stop(); t.Dispose(); }
            };
            t.Start();
        }
        // a janela abre aparecendo aos poucos
        public static void FadeIn(Form f) {
            f.Opacity = 0;
            f.Shown += delegate {
                var clock = System.Diagnostics.Stopwatch.StartNew();
                var t = new Timer { Interval = 10 };
                t.Tick += delegate {
                    double k = Math.Min(1.0, clock.ElapsedMilliseconds / 170.0);
                    if (!f.IsDisposed) f.Opacity = k;
                    if (k >= 1 || f.IsDisposed) { t.Stop(); t.Dispose(); }
                };
                t.Start();
            };
        }
        public static GraphicsPath Round(RectangleF r, float rad) {
            var p = new GraphicsPath(); float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }
        // barra de rolagem escura do tema do Windows 10/11
        public static void DarkScroll(Control c) {
            c.HandleCreated += delegate { try { SetWindowTheme(c.Handle, "DarkMode_Explorer", null); } catch { } };
        }
    }
}
'@
    $script:UiKitOk = $true
} catch {}

function New-Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h = 34) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = L $text; $b.Left = $x; $b.Top = $y; $b.Width = $w; $b.Height = $h
    # texto traduzido maior que o botão: alarga (o espaço do ícone conta)
    $need = [System.Windows.Forms.TextRenderer]::MeasureText($b.Text, $font).Width + 28
    if ($need -gt $w) { $b.Width = $need }
    $b.FlatStyle = 'Flat'; $b.BackColor = $panelBg; $b.ForeColor = $fg
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $b.Font = $font
    return $b
}

function New-Label([string]$text, [int]$x, [int]$y, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Left = $x; $l.Top = $y; $l.AutoSize = $true
    if ($color) { $l.ForeColor = $color }
    return $l
}

function New-Dialog([string]$title, [int]$w, [int]$h) {
    $d = New-Object System.Windows.Forms.Form
    [PL.Lang]::Hook($d); [PL.Dark]::Use($d)
    $d.Text = $title; $d.ClientSize = New-Object System.Drawing.Size($w, $h)
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $d.StartPosition = 'CenterParent'; $d.ShowInTaskbar = $false
    $d.BackColor = $bg; $d.ForeColor = $fg; $d.Font = $font
    return $d
}

# ---------------------------------------------------------------- tela: configurações do jogo

function Update-SliderLabel($tb) {
    $v = $tb.Value
    if ($tb.Tag.key -eq 'volume') {
        if ($v -eq 0) { $tb.Tag.valueLabel.Text = 'mudo' } else { $tb.Tag.valueLabel.Text = "$($v * 10)%" }
        return
    }
    if (-not $tb.Enabled) { $tb.Tag.valueLabel.Text = 'só com placa NVIDIA' }
    elseif ($v -gt 0) { $tb.Tag.valueLabel.Text = "+$v%" }
    elseif ($v -lt 0) { $tb.Tag.valueLabel.Text = "$v%" }
    else { $tb.Tag.valueLabel.Text = 'normal' }
}

function Set-DialogControl($ctl, $value) {
    if ($ctl -is [System.Windows.Forms.CheckBox]) { $ctl.Checked = [bool]$value; return }
    if ($ctl -is [System.Windows.Forms.TextBox]) { $ctl.Text = [string]$value; return }
    if ($ctl -is [System.Windows.Forms.TrackBar]) {
        if ($ctl.Tag.key -eq 'volume') { $value = [math]::Round([int]$value / 10) }   # barra em passos de 10%
        $ctl.Value = [math]::Max($ctl.Minimum, [math]::Min($ctl.Maximum, [int]$value))
        Update-SliderLabel $ctl
        return
    }
    $vals = $ctl.Tag.values
    for ($i = 0; $i -lt $vals.Count; $i++) {
        if ("$($vals[$i])" -eq "$value") { $ctl.SelectedIndex = $i; return }
    }
    if ($ctl.Items.Count) { $ctl.SelectedIndex = 0 }
}

function Get-DialogControl($ctl) {
    if ($ctl -is [System.Windows.Forms.CheckBox]) { return $ctl.Checked }
    if ($ctl -is [System.Windows.Forms.TextBox]) { return $ctl.Text.Trim() }
    if ($ctl -is [System.Windows.Forms.TrackBar]) {
        if ($ctl.Tag.key -eq 'volume') { return $ctl.Value * 10 }
        return $ctl.Value
    }
    return $ctl.Tag.values[$ctl.SelectedIndex]
}

function New-SettingsCard($parent, [int]$top) {
    if ($script:UiKitOk) { $c = New-Object PL.SetCard; [PL.UiKit]::Smooth($c) } else { $c = New-Object System.Windows.Forms.Panel }
    $c.Left = 12; $c.Top = $top; $c.Width = 586; $c.BackColor = $panelBg
    $parent.Controls.Add($c)
    return $c
}

function Show-SettingsPage([int]$i) {
    for ($n = 0; $n -lt $script:dlgPages.Count; $n++) { if ($n -ne $i) { $script:dlgPages[$n].Visible = $false } }
    $page = $script:dlgPages[$i]
    $page.Left = 0; $page.Visible = $true
    if ($script:UiKitOk) { [PL.UiKit]::SlideIn($page, 26) }
}

function Update-OnlineDnsBox {
    # DNS digitado errado não deixa salvar; vazio desliga o online
    $dns = Get-DialogControl $script:dlgControls.onlineDns
    $script:dlgOk.Enabled = (-not $dns) -or (Test-Ps2Dns $dns)
}

function Show-GameSettings($g, [bool]$forPlay) {
    $kind = Get-ConsoleKind $g
    $s = Get-GameSettings $g
    $defs = @($SettingDefs[$kind]) + $CommonDefs
    $port = Get-NativePort $g
    $script:dlgPort = $port
    if ($port) { $defs = $CommonDefs }   # port nativo tem as opções gráficas no launcher dele
    # opções que só valem para alguns jogos (correções e patches conhecidos)
    $tid = $null; if ($kind -eq 'PS4') { $tid = Get-Ps4TitleId $g.path }
    $extraKeys = @(Get-Ps4PatchKeys $tid)
    $ps2Fp = $null
    if ($kind -eq 'PS2') { $ps2Fp = Get-Ps2FpsPatch $g }
    if ($ps2Fp) { $extraKeys += 'fps60' }
    $hasFix = [bool](Get-GameFix $g)
    if ($hasFix -and (Get-GameFix $g).eltutz) { $extraKeys += 'officialEmu' }
    $defs = @($defs | Where-Object {
            (-not $_.cond) -or ($_.cond -eq 'fix' -and $hasFix) -or ($_.cond -like 'patch:*' -and $_.cond.Substring(6) -in $extraKeys)
        })

    $d = New-Dialog "Configurações - $($g.name)" 780 480
    if ($script:UiKitOk) { [PL.UiKit]::FadeIn($d) }
    $script:dlgControls = @{}
    $script:dlgApplying = $true
    $script:dlgKind = $kind
    $script:dlgFix = Get-GameFix $g

    # topo, abas e rodapé fixos; cada aba mostra só o seu assunto, então não precisa rolar
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'; $body.BackColor = $bg
    $head = New-Object System.Windows.Forms.Panel
    $head.Dock = 'Top'; $head.Height = 84; $head.BackColor = $panelBg
    $foot = New-Object System.Windows.Forms.Panel
    $foot.Dock = 'Bottom'; $foot.Height = 62; $foot.BackColor = $panelBg
    if ($script:UiKitOk) { $nav = New-Object PL.SetNav; $nav.Accent = $accent; $nav.ForeColor = $fg } else { $nav = New-Object System.Windows.Forms.Panel }
    $nav.Dock = 'Left'; $nav.Width = 168; $nav.BackColor = [System.Drawing.Color]::FromArgb(29, 29, 34)
    $d.Controls.AddRange(@($body, $nav, $head, $foot))

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Left = 16; $pic.Top = 9; $pic.Width = 50; $pic.Height = 66; $pic.SizeMode = 'Zoom'; $pic.BackColor = $panelBg
    try { $pic.Image = Get-DetailCover $g } catch {}
    $head.Controls.Add($pic)
    $lt = New-Label $g.name 78 14
    $lt.AutoSize = $false; $lt.Width = 430; $lt.Height = 28; $lt.AutoEllipsis = $true
    $lt.Font = $fontTitle; $lt.BackColor = $panelBg
    $head.Controls.Add($lt)
    $emu = switch ($kind) { 'PS2' { 'PCSX2' } 'PS3' { 'RPCS3' } default { if ($port) { "$($port.name) (port nativo)" } elseif ($s.eltutz) { 'shadPS4 eltutz (cuesta4)' } else { 'shadPS4' } } }
    $ls = New-Label "$($g.console)  -  roda no $emu" 79 46 $consoleColors[$g.console]
    $ls.BackColor = $panelBg
    $head.Controls.Add($ls)

    $lp = New-Label 'Predefinição' 524 10 $dim
    $lp.BackColor = $panelBg
    $head.Controls.Add($lp)
    $cbPreset = New-Object System.Windows.Forms.ComboBox
    $cbPreset.DropDownStyle = 'DropDownList'; $cbPreset.Left = 524; $cbPreset.Top = 34; $cbPreset.Width = 240
    $cbPreset.BackColor = $bg; $cbPreset.ForeColor = $fg; $cbPreset.FlatStyle = 'Flat'
    foreach ($n in $PresetNames) { [void]$cbPreset.Items.Add($n) }
    [void]$cbPreset.Items.Add('Personalizado')
    $idx = [array]::IndexOf($PresetNames, [string]$s.preset)
    if ($idx -lt 0) { $idx = 3 }
    $cbPreset.SelectedIndex = $idx
    $head.Controls.Add($cbPreset)
    $script:dlgPreset = $cbPreset

    # cada opção vai para a aba do seu assunto
    $byKey = @{}; foreach ($def in $defs) { $byKey[$def.key] = $def }
    $seen = @{}; $groups = @()
    foreach ($gr in $SettingGroups) {
        $inside = @($gr.keys | Where-Object { $byKey.ContainsKey($_) } | ForEach-Object { $seen[$_] = 1; $byKey[$_] })
        if ($inside.Count) { $groups += @{ title = $gr.title; defs = $inside } }
    }
    $rest = @($defs | Where-Object { -not $seen.ContainsKey($_.key) })
    if ($rest.Count) { $groups += @{ title = 'Outros'; defs = $rest } }

    $script:dlgPages = @()
    $pageH = 240
    foreach ($gr in $groups) {
    $page = New-Object System.Windows.Forms.Panel
    $page.Left = 0; $page.Top = 0; $page.Width = 612; $page.BackColor = $bg; $page.Visible = ($script:dlgPages.Count -eq 0)
    if ($script:UiKitOk) { [PL.UiKit]::Smooth($page) }
    $body.Controls.Add($page)
    $script:dlgPages += $page
    $card = New-SettingsCard $page 12
    $y = 12
    foreach ($def in $gr.defs) {
        if ($def.type -eq 'info') {
            # só informa: não é opção, não entra nas configurações salvas
            $rl = New-Label $def.label 16 ($y + 3); $rl.BackColor = $panelBg; $card.Controls.Add($rl)
            $ri = New-Label $def.text 300 ($y + 3) $dim; $ri.BackColor = $panelBg; $card.Controls.Add($ri)
            $y += 36
            continue
        }
        if ($def.type -eq 'combo') {
            $rl = New-Label $def.label 16 ($y + 3); $rl.BackColor = $panelBg; $card.Controls.Add($rl)
            $cb = New-Object System.Windows.Forms.ComboBox
            $cb.DropDownStyle = 'DropDownList'; $cb.Left = 274; $cb.Top = $y; $cb.Width = 296
            $cb.BackColor = $bg; $cb.ForeColor = $fg; $cb.FlatStyle = 'Flat'
            foreach ($o in $def.options) { [void]$cb.Items.Add($o[0]) }
            $cb.Tag = @{ key = $def.key; values = @($def.options | ForEach-Object { $_[1] }) }
            if ($def.key -notin $CommonDefaults.Keys) {
                $cb.Add_SelectedIndexChanged({ if (-not $script:dlgApplying) { $script:dlgPreset.SelectedIndex = 3 } })
            }
            $ctl = $cb
        } elseif ($def.type -eq 'slider') {
            # PS2: -100% a +100% (Shade Boost); PS3/PS4: 0 a +100% (vibração NVIDIA, só aumenta)
            $rl = New-Label $def.label 16 ($y + 5); $rl.BackColor = $panelBg; $card.Controls.Add($rl)
            $tb = New-Object System.Windows.Forms.TrackBar
            $tb.AutoSize = $false; $tb.Left = 296; $tb.Top = $y; $tb.Width = 204; $tb.Height = 30
            $tb.Minimum = -100; $tb.Maximum = 100; $tb.TickFrequency = 25; $tb.SmallChange = 5; $tb.LargeChange = 10
            $tb.TickStyle = 'None'; $tb.BackColor = $panelBg
            $vl = New-Label '' 506 ($y + 5)
            $vl.BackColor = $panelBg
            $tb.Tag = @{ key = $def.key; valueLabel = $vl }
            $tb.Add_ValueChanged({ Update-SliderLabel $this })
            if ($def.key -eq 'volume') {
                $tb.Minimum = 0; $tb.Maximum = 10; $tb.TickFrequency = 1; $tb.SmallChange = 1; $tb.LargeChange = 1
                if (-not $script:AudioOk) { $tb.Enabled = $false; $vl.ForeColor = $dim }
            } elseif ($kind -ne 'PS2') {
                $tb.Minimum = 0
                if (-not (Test-NvVibrance)) { $tb.Enabled = $false; $vl.ForeColor = $dim; $tb.Width = 130; $vl.Left = 432 }
            }
            $card.Controls.Add($vl)
            $ctl = $tb
        } elseif ($def.type -eq 'text') {
            $rl = New-Label $def.label 16 ($y + 3); $rl.BackColor = $panelBg; $card.Controls.Add($rl)
            $ctl = New-Object System.Windows.Forms.TextBox
            $ctl.Left = 300; $ctl.Top = $y; $ctl.Width = 270; $ctl.MaxLength = 15
            $ctl.BackColor = $bg; $ctl.ForeColor = $fg; $ctl.BorderStyle = 'FixedSingle'
            $ctl.Tag = @{ key = $def.key }
        } else {
            if ($script:UiKitOk) {
                $ctl = New-Object PL.Toggle
                $ctl.Accent = $accent; $ctl.Width = 562; $ctl.Height = 32; $ctl.Left = 12; $ctl.Top = $y - 3
            } else {
                $ctl = New-Object System.Windows.Forms.CheckBox
                $ctl.Left = 16; $ctl.Top = $y; $ctl.AutoSize = $true
            }
            $ctl.Text = $def.label; $ctl.BackColor = $panelBg
            $ctl.Tag = @{ key = $def.key }
            if ($def.key -notin $CommonDefaults.Keys) {
                $ctl.Add_CheckedChanged({ if (-not $script:dlgApplying) { $script:dlgPreset.SelectedIndex = 3 } })
            }
        }
        Set-DialogControl $ctl $s[$def.key]
        $script:dlgControls[$def.key] = $ctl
        $card.Controls.Add($ctl)
        $y += 36
        # PS2: o patch de 60 FPS pede a CPU do PS2 mais rápida; o launcher cuida disso sozinho e avisa aqui
        if ($def.key -eq 'fps60' -and $ps2Fp -and $ps2Fp.ee -gt 0) {
            $pct = @{ 1 = '130%'; 2 = '180%'; 3 = '300%' }[[int]$ps2Fp.ee]
            $hl = New-Label "A velocidade da CPU do PS2 vai para $pct sozinha enquanto o jogo roda (o patch precisa). Não precisa mudar nada." 16 ($y - 6) $dim
            $hl.MaximumSize = New-Object System.Drawing.Size(554, 0); $hl.BackColor = $panelBg
            $card.Controls.Add($hl)
            $y += $hl.PreferredHeight + 6
        }
    }
    $card.Height = $y + 4
    $page.Height = $card.Bottom + 12
    $pageH = [math]::Max($pageH, $page.Height)
    }

    # avisos ficam embaixo do cartão da primeira aba
    $first = $script:dlgPages[0]
    $noteY = $first.Controls[0].Bottom + 10
    $notes = @()
    $warn = Get-PatchVersionWarning $g
    if ($warn) { $notes += , @($warn, [System.Drawing.Color]::FromArgb(255, 190, 90)) }
    if ($kind -eq 'PS4') {
        if ($port) { $note = "Gráficos (resolução, FPS, upscaler) são ajustados no próprio $($port.name): botão abaixo ou menu dentro do jogo." }
        else { $note = 'Estas opções valem só para este jogo: o launcher grava a configuração do shadPS4 deste jogo antes de abrir.' }
        $notes += , @($note, $dim)
    }
    foreach ($nt in $notes) {
        $l = New-Label $nt[0] 16 $noteY $nt[1]
        $l.MaximumSize = New-Object System.Drawing.Size(582, 0)
        $first.Controls.Add($l)
        $noteY += $l.PreferredHeight + 8
    }
    $first.Height = [math]::Max($first.Height, $noteY + 6)
    $pageH = [math]::Max($pageH, $first.Height)

    if ($script:UiKitOk) {
        foreach ($gr in $groups) { $nav.Items.Add((L $gr.title)) }
        $nav.Add_SelectedChanged({ Show-SettingsPage $this.SelectedIndex })
    } else {
        for ($n = 0; $n -lt $groups.Count; $n++) {
            $nb = New-Button $groups[$n].title 10 (12 + $n * 44) 148 38
            $nb.Tag = $n
            $nb.Add_Click({ Show-SettingsPage $this.Tag })
            $nav.Controls.Add($nb)
        }
    }

    # com o 60 FPS ligado, a velocidade da CPU do PS2 fica por conta do patch
    if ($ps2Fp -and $ps2Fp.ee -gt 0 -and $script:dlgControls.ContainsKey('fps60') -and $script:dlgControls.ContainsKey('eeCycle')) {
        $script:dlgControls.eeCycle.Enabled = -not $script:dlgControls.fps60.Checked
        $script:dlgControls.fps60.Add_CheckedChanged({ $script:dlgControls.eeCycle.Enabled = -not $this.Checked })
    }

    # 60 / 90 / 120 FPS: um patch de FPS por vez (marcar um desmarca os outros)
    $fpsBoxes = @($OwnPatchOptions | Where-Object { $script:dlgControls.ContainsKey($_) })
    if ($fpsBoxes.Count -gt 1) {
        foreach ($k in $fpsBoxes) {
            $script:dlgControls[$k].Tag = $k
            $script:dlgControls[$k].Add_CheckedChanged({
                    if (-not $this.Checked) { return }
                    foreach ($o in $OwnPatchOptions) { if ($o -ne $this.Tag -and $script:dlgControls.ContainsKey($o)) { $script:dlgControls[$o].Checked = $false } }
                })
        }
    }

    $cbPreset.Add_SelectedIndexChanged({
            $i = $script:dlgPreset.SelectedIndex
            if ($i -lt 0 -or $i -gt 2) { return }
            $vals = $Presets[$script:dlgKind][$PresetNames[$i]]
            $script:dlgApplying = $true
            foreach ($k in $vals.Keys) { if ($script:dlgControls.ContainsKey($k)) { Set-DialogControl $script:dlgControls[$k] $vals[$k] } }
            # a correção conhecida do jogo continua valendo em qualquer predefinição
            if ($script:dlgFix) { foreach ($k in $script:dlgFix.Keys) { if ($script:dlgControls.ContainsKey($k)) { Set-DialogControl $script:dlgControls[$k] $script:dlgFix[$k] } } }
            $script:dlgApplying = $false
        })

    $chkShow = New-Object System.Windows.Forms.CheckBox
    $chkShow.Text = 'Mostrar esta tela antes de cada jogo'; $chkShow.Left = 180; $chkShow.Top = 21; $chkShow.AutoSize = $true
    $chkShow.ForeColor = $dim; $chkShow.Checked = [bool]$script:Cfg.showSettings
    $foot.Controls.Add($chkShow)
    $y = 11

    if ($forPlay) { $okText = 'JOGAR' } else { $okText = 'Salvar' }
    $btnOk = New-Button $okText 634 $y 130 40
    $btnOk.BackColor = $accent; $btnOk.Font = $fontBold; $btnOk.DialogResult = 'OK'
    $btnOk.FlatAppearance.BorderColor = $accent
    $btnCancel = New-Button 'Cancelar' 494 $y 130 40
    $btnCancel.BackColor = $bg; $btnCancel.DialogResult = 'Cancel'
    $foot.Controls.AddRange(@($btnOk, $btnCancel))
    $d.AcceptButton = $btnOk; $d.CancelButton = $btnCancel
    $d.ActiveControl = $btnOk   # sem isto a primeira lista abre com a faixa azul de seleção
    if ($script:dlgControls.ContainsKey('onlineDns')) {
        $script:dlgOk = $btnOk
        $script:dlgControls.onlineDns.Add_TextChanged({ Update-OnlineDnsBox })
        Update-OnlineDnsBox
    }
    if ($port) {
        $btnSp = New-Button "Abrir $($port.name)" 16 $y 180 40
        $btnSp.BackColor = $bg; $btnSp.DialogResult = 'Retry'
        $foot.Controls.Add($btnSp)
    }
    if ($kind -eq 'PS2') {
        $script:dlgGame = $g
        $btnTex = New-Button 'Texturas HD...' 16 $y 150 40
        $btnTex.BackColor = $bg
        $btnTex.Add_Click({ Show-TexturesDialog $script:dlgGame $this.FindForm() })
        $foot.Controls.Add($btnTex)
    }
    # só em tela bem pequena a aba precisa rolar
    $maxH = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea.Height - 80
    $wantH = $head.Height + $pageH + $foot.Height
    if ($wantH -gt $maxH) { $body.AutoScroll = $true; if ($script:UiKitOk) { [PL.UiKit]::DarkScroll($body) } }
    $d.ClientSize = New-Object System.Drawing.Size(780, [math]::Min($maxH, $wantH))

    $script:dlgApplying = $false
    $result = $d.ShowDialog($form)
    if ($result -eq 'Cancel') { return 'cancel' }

    $out = [ordered]@{}
    $pi = $cbPreset.SelectedIndex
    if ($pi -ge 0 -and $pi -le 2) { $out.preset = $PresetNames[$pi] } else { $out.preset = 'Personalizado' }
    foreach ($k in $script:dlgControls.Keys) { $out[$k] = Get-DialogControl $script:dlgControls[$k] }
    $g | Add-Member -NotePropertyName settings -NotePropertyValue ([pscustomobject]$out) -Force
    $script:Cfg.showSettings = $chkShow.Checked
    Save-Config

    if ($result -eq 'Retry') {
        $k = $script:dlgPort.key
        if (-not $script:Cfg[$k] -or -not (Test-Path -LiteralPath $script:Cfg[$k])) { [void](Require-Emu $k) }
        if ($script:Cfg[$k] -and (Test-Path -LiteralPath $script:Cfg[$k])) { Open-PortSetup $script:dlgPort $g }
        return 'cancel'
    }
    if ($forPlay) { return 'play' }
    return 'save'
}

# ---------------------------------------------------------------- tela: texturas HD (PS2)

function Show-TexturesDialog($g, $owner) {
    $exe = $script:Cfg.pcsx2
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { [void](Require-Emu 'pcsx2'); $exe = $script:Cfg.pcsx2 }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return }
    $script:texExe = $exe
    $script:texGame = $g

    $d = New-Dialog "Texturas HD - $($g.name)" 640 330
    $t = New-Label 'Texturas HD' 20 14; $t.Font = $fontTitle
    $info = New-Label ("Instale pacotes de texturas feitos para o PCSX2 (procure por `"<código do jogo> texture pack`"). " +
        "Aceita .zip, pasta, e .7z/.rar com o 7-Zip instalado. Só jogos de PS2: RPCS3 e shadPS4 não suportam troca de texturas.") 22 50 $dim
    $info.MaximumSize = New-Object System.Drawing.Size(596, 0)
    $lSerial = New-Label 'Código do jogo' 22 122
    $script:texSerial = New-Object System.Windows.Forms.TextBox
    $script:texSerial.Left = 160; $script:texSerial.Top = 119; $script:texSerial.Width = 140
    $script:texSerial.BackColor = $panelBg; $script:texSerial.ForeColor = $fg; $script:texSerial.BorderStyle = 'FixedSingle'
    $script:texSerial.CharacterCasing = 'Upper'
    $serial = Get-GameSerial $g
    if ($serial) { $script:texSerial.Text = $serial }
    $lHint = New-Label 'ex: SCUS-97481 (lido da ISO automaticamente)' 310 122 $dim
    $script:texStatus = New-Label '' 22 160
    $script:texStatus.Font = $fontBold

    $bZip = New-Button 'Instalar de arquivo...' 22 205 180 40
    $bZip.BackColor = $accent; $bZip.Font = $fontBold
    $bDir = New-Button 'Instalar de pasta...' 210 205 160 40
    $bOpen = New-Button 'Abrir pasta' 378 205 120 40
    $bDel = New-Button 'Remover' 506 205 112 40
    $bClose = New-Button 'Fechar' 498 262 120 38
    $bClose.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($t, $info, $lSerial, $script:texSerial, $lHint, $script:texStatus, $bZip, $bDir, $bOpen, $bDel, $bClose))
    $d.CancelButton = $bClose
    $d.ClientSize = New-Object System.Drawing.Size(640, 316)

    # código válido do jogo (e guarda no jogo); $null se o campo estiver errado
    $script:texGetSerial = {
        $s = $script:texSerial.Text.Trim()
        if ($s -notmatch '^[A-Z]{4}-\d{5}$') {
            [void][PL.Lang]::Msg('Digite o código do jogo no formato ABCD-12345 (aparece na capa do jogo ou na lista do PCSX2).', 'Texturas HD')
            return $null
        }
        if ($script:texGame.serial -ne $s) {
            $script:texGame | Add-Member -NotePropertyName serial -NotePropertyValue $s -Force
            Save-Config
        }
        return $s
    }
    $script:texRefresh = {
        $s = $script:texSerial.Text.Trim()
        if ($s -notmatch '^[A-Z]{4}-\d{5}$') { $script:texStatus.Text = 'Informe o código do jogo'; $script:texStatus.ForeColor = $badColor; return }
        $dir = Get-Pcsx2TextureDir $script:texExe $s
        $n = 0
        if (Test-Path -LiteralPath $dir) { $n = @(Get-ChildItem -LiteralPath $dir -Recurse -File).Count }
        if ($n) { $script:texStatus.Text = "Pacote instalado: $n arquivo(s) de textura"; $script:texStatus.ForeColor = $okColor }
        else { $script:texStatus.Text = 'Nenhum pacote de texturas instalado'; $script:texStatus.ForeColor = $dim }
    }
    $script:texInstall = {
        param([string]$source)
        $s = & $script:texGetSerial
        if (-not $s) { return }
        $script:texStatus.Text = 'Instalando... (pacotes grandes podem levar alguns minutos)'; $script:texStatus.ForeColor = $fg
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $n = Install-TexturePack $script:texExe $s $source
            & $script:texRefresh
            Set-Status "Texturas HD instaladas para $($script:texGame.name): $n arquivo(s)."
        } catch {
            & $script:texRefresh
            [void][PL.Lang]::Msg("Não foi possível instalar: $($_.Exception.Message)", 'Texturas HD')
        }
    }
    & $script:texRefresh
    $script:texSerial.Add_TextChanged({ & $script:texRefresh })

    $bZip.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Title = L 'Selecione o pacote de texturas'
            $dlg.Filter = L 'Pacote de texturas|*.zip;*.7z;*.rar|Todos|*.*'
            if ($dlg.ShowDialog() -eq 'OK') { & $script:texInstall $dlg.FileName }
        })
    $bDir.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = L 'Escolha a pasta do pacote de texturas (já extraída)'
            if ($dlg.ShowDialog() -eq 'OK') { & $script:texInstall $dlg.SelectedPath }
        })
    $bOpen.Add_Click({
            $s = & $script:texGetSerial
            if (-not $s) { return }
            $dir = Get-Pcsx2TextureDir $script:texExe $s
            New-Item -ItemType Directory -Force $dir | Out-Null
            Start-Process explorer.exe "`"$dir`""
        })
    $bDel.Add_Click({
            $s = & $script:texGetSerial
            if (-not $s) { return }
            $dir = Split-Path (Get-Pcsx2TextureDir $script:texExe $s)
            if (-not (Test-Path -LiteralPath $dir)) { return }
            $r = [PL.Lang]::Msg("Remover o pacote de texturas de $($script:texGame.name)?", 'Texturas HD', 'YesNo')
            if ($r -eq 'Yes') { Remove-Item -LiteralPath $dir -Recurse -Force; & $script:texRefresh }
        })

    if ($owner) { [void]$d.ShowDialog($owner) } else { [void]$d.ShowDialog($form) }
}

# ---------------------------------------------------------------- tela: emuladores

function Get-EmuVersion([string]$key) {
    $exe = $script:Cfg[$key]
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $null }
    $v = Join-Path (Join-Path $EmuRoot $key) '.versao'
    if ($exe.ToLower().StartsWith($EmuRoot.ToLower()) -and (Test-Path $v)) { return (Get-Content $v -Raw).Trim() }
    return 'instalado'
}

function Run-Installer([string[]]$only) {
    $argStr = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $Root 'Instalar-Emuladores.ps1')`""
    if ($only) { $argStr += ' -Only ' + ($only -join ',') }
    $argStr += " -Lang $script:Lang"
    $p = Start-Process powershell -ArgumentList $argStr -PassThru
    Set-Status 'Instalando emuladores... acompanhe na janela preta.'
    while (-not $p.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200 }
    Update-EmuPaths $true
    Save-Config
    Set-Status 'Instalação dos emuladores concluída.'
}

function Get-Ps2BiosStatus([string]$exe) {
    if (-not (Test-Pcsx2Ready $exe)) { return $null }
    $txt = Get-Content -LiteralPath (Get-Pcsx2Ini $exe) -Raw
    [void]($txt -cmatch '(?m)^\s*BIOS\s*=[ \t]*(\S[^\r\n]*)')
    $name = $Matches[1].Trim()
    $info = Get-Ps2BiosInfo (Join-Path (Join-Path (Get-Pcsx2DataDir $exe) 'bios') $name)
    if ($info) { return "$name  (v$($info.version), $($info.region))" }
    return $name
}

function Show-Ps2BiosDialog {
    # Tela própria do launcher no lugar do assistente do PCSX2. Retorna $true se a BIOS ficou configurada.
    $exe = $script:Cfg.pcsx2
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { [void](Require-Emu 'pcsx2'); $exe = $script:Cfg.pcsx2 }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $false }
    $script:biosExe = $exe

    $d = New-Dialog 'BIOS do PS2' 620 300
    $t = New-Label 'BIOS do PS2' 20 14; $t.Font = $fontTitle
    $info = New-Label "Os jogos de PS2 precisam da BIOS do console (arquivo .bin de cerca de 4 MB).`nAdicione uma ou várias e escolha qual usar; o launcher configura o resto sozinho." 22 50 $dim
    $info.MaximumSize = New-Object System.Drawing.Size(576, 0)
    $lUse = New-Label 'BIOS em uso' 22 115
    $script:biosCombo = New-Object System.Windows.Forms.ComboBox
    $script:biosCombo.DropDownStyle = 'DropDownList'; $script:biosCombo.Left = 140; $script:biosCombo.Top = 111; $script:biosCombo.Width = 458
    $script:biosCombo.BackColor = $panelBg; $script:biosCombo.ForeColor = $fg; $script:biosCombo.FlatStyle = 'Flat'
    $script:biosStatus = New-Label '' 22 152
    $script:biosStatus.Font = $fontBold
    $bFiles = New-Button 'Adicionar arquivo(s)...' 22 200 200 40
    $bFiles.BackColor = $accent; $bFiles.Font = $fontBold
    $bFolder = New-Button 'Adicionar pasta...' 232 200 170 40
    $bClose = New-Button 'Fechar' 478 200 120 40
    $bClose.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($t, $info, $lUse, $script:biosCombo, $script:biosStatus, $bFiles, $bFolder, $bClose))
    $d.CancelButton = $bClose
    $d.ClientSize = New-Object System.Drawing.Size(620, 260)

    # preenche a lista com as BIOS instaladas e marca a que está em uso
    $script:refreshBios = {
        $script:biosFilling = $true
        $script:biosList = @(Get-InstalledPs2Bioses $script:biosExe)
        $script:biosCombo.Items.Clear()
        foreach ($b in $script:biosList) { [void]$script:biosCombo.Items.Add($b.label) }
        $cur = $null
        if (Test-Pcsx2Ready $script:biosExe) {
            $txt = Get-Content -LiteralPath (Get-Pcsx2Ini $script:biosExe) -Raw
            if ($txt -cmatch '(?m)^\s*BIOS\s*=[ \t]*(\S[^\r\n]*)') { $cur = $Matches[1].Trim() }
        }
        for ($i = 0; $i -lt $script:biosList.Count; $i++) { if ($script:biosList[$i].name -eq $cur) { $script:biosCombo.SelectedIndex = $i } }
        $script:biosFilling = $false
        if ($cur) { $script:biosStatus.Text = "Pronto para jogar  ($($script:biosList.Count) BIOS instalada(s))"; $script:biosStatus.ForeColor = $okColor }
        else { $script:biosStatus.Text = 'Nenhuma BIOS configurada'; $script:biosStatus.ForeColor = $badColor }
    }
    $script:importBios = {
        param([string[]]$files)
        $n = Import-Ps2Bioses $script:biosExe $files
        Select-DefaultPs2Bios $script:biosExe
        & $script:refreshBios
        if ($n -eq 0) { [void][PL.Lang]::Msg('Nenhuma BIOS nova encontrada (arquivos inválidos ou já adicionados).', 'BIOS do PS2') }
        else { Set-Status "$n BIOS do PS2 adicionada(s)." }
    }
    & $script:refreshBios

    $script:biosCombo.Add_SelectedIndexChanged({
            if ($script:biosFilling -or $script:biosCombo.SelectedIndex -lt 0) { return }
            Select-Pcsx2Bios $script:biosExe $script:biosList[$script:biosCombo.SelectedIndex].name
            & $script:refreshBios
        })
    $bFiles.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Title = L 'Selecione a(s) BIOS do PS2'
            $dlg.Filter = L 'BIOS PS2|*.bin;*.rom0;*.rom|Todos|*.*'
            $dlg.Multiselect = $true
            if ($dlg.ShowDialog() -eq 'OK') { & $script:importBios $dlg.FileNames }
        })
    $bFolder.Add_Click({
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = L 'Escolha a pasta com as BIOS do PS2'
            if ($dlg.ShowDialog() -eq 'OK') {
                & $script:importBios @(Get-ChildItem -LiteralPath $dlg.SelectedPath -File | ForEach-Object FullName)
            }
        })

    [void]$d.ShowDialog($form)
    if ($script:emuStatus) { Update-EmuStatus }
    return (Test-Pcsx2Ready $exe)
}

# ---------------------------------------------------------------- conquistas / troféus
# PS2: RetroAchievements pelo PCSX2. O launcher faz o login e guarda só o token no PCSX2.ini (nunca a senha).
# PS3: troféus nativos do RPCS3.

function Get-IniSection([string]$path, [string]$section) {
    $h = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $h }
    $in = $false
    foreach ($l in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        if ($l.Trim().StartsWith('[')) { $in = ($l.Trim() -eq "[$section]"); continue }
        if ($in -and $l -match '^\s*([^=]+?)\s*=\s*(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() }
    }
    return $h
}

function Invoke-RaLogin([string]$user, [string]$pass) {
    # mesma chamada que o PCSX2 faz (login2); a senha vai no corpo do POST, por HTTPS
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $body = 'r=login2&u=' + [uri]::EscapeDataString($user) + '&p=' + [uri]::EscapeDataString($pass)
    $req = [Net.HttpWebRequest]::Create('https://retroachievements.org/dorequest.php')
    $req.Method = 'POST'; $req.ContentType = 'application/x-www-form-urlencoded'; $req.UserAgent = 'TriviumHub/1.0 (Windows)'; $req.Timeout = 15000
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    try {
        $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
        $resp = $req.GetResponse()
    } catch [Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { return @{ ok = $false; error = 'Sem conexão com retroachievements.org.' } }
    }
    $txt = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd(); $resp.Close()
    try { $j = $txt | ConvertFrom-Json } catch { return @{ ok = $false; error = 'Resposta inválida do RetroAchievements.' } }
    if ($j.Success -and $j.Token) { return @{ ok = $true; user = [string]$j.User; token = [string]$j.Token; score = $j.Score } }
    if ($j.Code -eq 'invalid_credentials') { return @{ ok = $false; error = 'Usuário ou senha incorretos.' } }
    return @{ ok = $false; error = [string]$j.Error }
}

function Show-AchievementsDialog {
    $exe = $script:Cfg.pcsx2
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { [void](Require-Emu 'pcsx2'); $exe = $script:Cfg.pcsx2 }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return }
    $script:achIni = Get-Pcsx2Ini $exe

    $d = New-Dialog 'Conquistas e troféus' 640 620
    $t = New-Label 'Conquistas e troféus' 20 14; $t.Font = $fontTitle

    $h2 = New-Label 'PS2  -  RetroAchievements' 22 56; $h2.Font = $fontBold
    $i2 = New-Label "Conquistas para jogos de PS2 pelo site RetroAchievements.org (conta grátis). Aparecem na tela quando você desbloqueia; a lista completa do jogo fica no menu de pausa (Select + Start no controle).`nNem todo jogo de PS2 tem conquistas no site." 22 80 $dim
    $i2.MaximumSize = New-Object System.Drawing.Size(596, 0)
    $script:achStatus = New-Label '' 22 172; $script:achStatus.Font = $fontBold

    $lU = New-Label 'Usuário' 22 210
    $script:achUser = New-Object System.Windows.Forms.TextBox
    $script:achUser.Left = 90; $script:achUser.Top = 207; $script:achUser.Width = 170
    $lP = New-Label 'Senha' 272 210
    $script:achPass = New-Object System.Windows.Forms.TextBox
    $script:achPass.Left = 322; $script:achPass.Top = 207; $script:achPass.Width = 150; $script:achPass.UseSystemPasswordChar = $true
    foreach ($tb in $script:achUser, $script:achPass) { $tb.BackColor = $panelBg; $tb.ForeColor = $fg; $tb.BorderStyle = 'FixedSingle' }
    $script:achLogin = New-Button 'Entrar' 482 203 136 32
    $script:achLogin.BackColor = $accent; $script:achLogin.Font = $fontBold
    $script:achLogout = New-Button 'Sair da conta' 482 203 136 32
    $lnk = New-Object System.Windows.Forms.LinkLabel
    $lnk.Text = 'Não tem conta? Criar conta grátis no RetroAchievements'; $lnk.Left = 22; $lnk.Top = 244; $lnk.AutoSize = $true
    $lnk.LinkColor = [System.Drawing.Color]::FromArgb(130, 160, 255)
    $lnk.Add_LinkClicked({ Start-Process 'https://retroachievements.org/createaccount.php' })

    $a = Get-IniSection $script:achIni 'Achievements'
    $script:achEnabled = New-Object System.Windows.Forms.CheckBox
    $script:achEnabled.Text = 'Ativar conquistas nos jogos de PS2'; $script:achEnabled.Left = 22; $script:achEnabled.Top = 276; $script:achEnabled.AutoSize = $true
    $script:achHardcore = New-Object System.Windows.Forms.CheckBox
    $script:achHardcore.Text = 'Modo Hardcore (conta no ranking; desativa save state, câmera lenta e trapaças)'; $script:achHardcore.Left = 22; $script:achHardcore.Top = 304; $script:achHardcore.AutoSize = $true
    $script:achSound = New-Object System.Windows.Forms.CheckBox
    $script:achSound.Text = 'Som ao desbloquear'; $script:achSound.Left = 22; $script:achSound.Top = 332; $script:achSound.AutoSize = $true
    $script:achEnabled.Checked = ($a.Enabled -eq 'true')
    $script:achHardcore.Checked = ($a.ChallengeMode -eq 'true')
    $script:achSound.Checked = ($a.SoundEffects -ne 'false')

    $h3 = New-Label 'PS3  -  Troféus' 22 380; $h3.Font = $fontBold
    $i3 = New-Label 'Os troféus do PS3 (inclusive a platina) já funcionam no RPCS3 e aparecem na tela quando desbloqueados. Para ver a lista: botão abaixo > menu Gerenciar > Troféus.' 22 404 $dim
    $i3.MaximumSize = New-Object System.Drawing.Size(596, 0)
    $script:achTrophyPopup = New-Object System.Windows.Forms.CheckBox
    $script:achTrophyPopup.Text = 'Mostrar aviso de troféu na tela'; $script:achTrophyPopup.Left = 22; $script:achTrophyPopup.Top = 452; $script:achTrophyPopup.AutoSize = $true
    $rp = $script:Cfg.rpcs3
    $script:achRpcs3Ini = $null
    if ($rp -and (Test-Path -LiteralPath $rp)) {
        $script:achRpcs3Ini = Join-Path (Split-Path $rp) 'GuiConfigs\CurrentSettings.ini'
        $script:achTrophyPopup.Checked = ((Get-IniSection $script:achRpcs3Ini 'Meta').showTrophyPopups -ne 'false')
    } else { $script:achTrophyPopup.Enabled = $false }
    $bTroph = New-Button 'Ver troféus (RPCS3)' 330 446 180 32
    $bTroph.Enabled = [bool]$script:achRpcs3Ini

    $h4 = New-Label 'PS4' 22 500; $h4.Font = $fontBold
    $i4 = New-Label 'shadPS4: os troféus precisam da chave de troféus do seu próprio PS4, configurada no shadPS4.' 22 524 $dim
    $i4.MaximumSize = New-Object System.Drawing.Size(596, 0)

    $bClose = New-Button 'Fechar' 498 570 120 38
    $bClose.DialogResult = 'OK'
    $d.Controls.AddRange(@($t, $h2, $i2, $script:achStatus, $lU, $script:achUser, $lP, $script:achPass, $script:achLogin, $script:achLogout, $lnk,
            $script:achEnabled, $script:achHardcore, $script:achSound, $h3, $i3, $script:achTrophyPopup, $bTroph, $h4, $i4, $bClose))
    $d.AcceptButton = $script:achLogin; $d.CancelButton = $bClose

    $script:achRefresh = {
        $a = Get-IniSection $script:achIni 'Achievements'
        $logged = [bool](Get-RaAccount)
        if ($logged) { $script:achStatus.Text = "Conectado como $($a.Username)"; $script:achStatus.ForeColor = $okColor }
        else { $script:achStatus.Text = 'Não conectado'; $script:achStatus.ForeColor = $badColor }
        $script:achUser.Enabled = -not $logged; $script:achPass.Enabled = -not $logged
        if ($logged) { $script:achUser.Text = $a.Username }
        $script:achLogin.Visible = -not $logged; $script:achLogout.Visible = $logged
    }
    & $script:achRefresh

    $script:achLogin.Add_Click({
            $u = $script:achUser.Text.Trim(); $p = $script:achPass.Text
            if (-not $u -or -not $p) { $script:achStatus.Text = 'Digite usuário e senha.'; $script:achStatus.ForeColor = $badColor; return }
            $script:achStatus.Text = 'Entrando...'; $script:achStatus.ForeColor = $dim; $script:achStatus.Refresh()
            $r = Invoke-RaLogin $u $p
            $script:achPass.Text = ''
            if (-not $r.ok) { $script:achStatus.Text = $r.error; $script:achStatus.ForeColor = $badColor; return }
            $ts = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
            Set-IniValues $script:achIni ([ordered]@{ 'Achievements' = [ordered]@{ Enabled = $true; Username = $r.user; Token = $r.token; LoginTimestamp = $ts } })
            # PCSX2 2.x lê o token de secrets.ini
            $sec = Join-Path (Split-Path $script:achIni) 'secrets.ini'
            if (Test-Path -LiteralPath $sec) { Set-IniValues $sec ([ordered]@{ 'Achievements' = [ordered]@{ Token = $r.token } }) }
            $script:achEnabled.Checked = $true
            & $script:achRefresh
            Set-Status "RetroAchievements: conectado como $($r.user)."
        })
    $script:achLogout.Add_Click({
            Set-IniValues $script:achIni ([ordered]@{ 'Achievements' = [ordered]@{ Username = ''; Token = ''; LoginTimestamp = '' } })
            $sec = Join-Path (Split-Path $script:achIni) 'secrets.ini'
            if (Test-Path -LiteralPath $sec) { Set-IniValues $sec ([ordered]@{ 'Achievements' = [ordered]@{ Token = '' } }) }
            Remove-Item -LiteralPath (Join-Path $TrophyDir 'ra.json') -ErrorAction SilentlyContinue
            & $script:achRefresh
        })
    $bTroph.Add_Click({
            [void][PL.Lang]::Msg('O RPCS3 vai abrir. Lá, vá no menu Gerenciar (Manage) > Troféus (Trophies).', 'Troféus do PS3')
            Start-Emu $script:Cfg.rpcs3 @() 'setup' $null
        })

    [void]$d.ShowDialog($form)
    Set-IniValues $script:achIni ([ordered]@{ 'Achievements' = [ordered]@{
                Enabled = $script:achEnabled.Checked; ChallengeMode = $script:achHardcore.Checked
                SoundEffects = $script:achSound.Checked; Notifications = $true; Overlays = $true
            }
        })
    if ($script:achRpcs3Ini) { Set-IniValues $script:achRpcs3Ini @{ 'Meta' = @{ showTrophyPopups = $script:achTrophyPopup.Checked } } '=' }
}

# ---------------------------------------------------------------- troféus (aba Conquistas)
# PS3: arquivos do RPCS3 (dev_hdd0\home\<usuário>\trophy\<NPWR...>: TROPCONF.SFM, TROPUSR.DAT e TROPxxx.PNG)
# PS4: arquivos do shadPS4 (user\trophy\<NPWR...>\Xml e Icons; desbloqueios em user\home\<id>\trophy\<NPWR...>.xml)
# PS2: RetroAchievements com a conta já conectada no PCSX2 (só leitura), em segundo plano e guardado em cache
$TrophyDir = Join-Path $Root 'cache\conquistas'
$TrophyGrades = @('P', 'G', 'S', 'B')
$TrophyPoints = @{ P = 300; G = 90; S = 30; B = 15 }   # pontos de cada tipo no PS5 (usados para o nível)
$TrophyNames = @{ P = 'Platina'; G = 'Ouro'; S = 'Prata'; B = 'Bronze' }
$TrophyColors = @{
    P = [System.Drawing.Color]::FromArgb(170, 196, 236); G = [System.Drawing.Color]::FromArgb(234, 188, 72)
    S = [System.Drawing.Color]::FromArgb(188, 196, 208); B = [System.Drawing.Color]::FromArgb(204, 130, 80)
}

function New-RectF($x, $y, $w, $h) { return New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]$h) }

function Draw-TrophyCup($gr, [single]$x, [single]$y, [single]$s, $color) {
    # taça desenhada (a fonte de ícones do Windows não tem troféu)
    $br = New-Object System.Drawing.SolidBrush($color)
    $pen = New-Object System.Drawing.Pen($color, [single][math]::Max(1.4, $s * 0.08))
    $bowl = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bowl.AddArc((New-RectF ($x + 0.22 * $s) ($y - 0.16 * $s) (0.56 * $s) (0.7 * $s)), 0, 180)
    $bowl.CloseFigure()
    $gr.FillPath($br, $bowl); $bowl.Dispose()
    $gr.FillRectangle($br, (New-RectF ($x + 0.22 * $s) ($y + 0.05 * $s) (0.56 * $s) (0.15 * $s)))
    $gr.DrawArc($pen, (New-RectF ($x + 0.07 * $s) ($y + 0.1 * $s) (0.24 * $s) (0.24 * $s)), 90, 180)
    $gr.DrawArc($pen, (New-RectF ($x + 0.69 * $s) ($y + 0.1 * $s) (0.24 * $s) (0.24 * $s)), 270, 180)
    $gr.FillRectangle($br, (New-RectF ($x + 0.45 * $s) ($y + 0.5 * $s) (0.1 * $s) (0.2 * $s)))
    $gr.FillRectangle($br, (New-RectF ($x + 0.31 * $s) ($y + 0.69 * $s) (0.38 * $s) (0.09 * $s)))
    $gr.FillRectangle($br, (New-RectF ($x + 0.25 * $s) ($y + 0.8 * $s) (0.5 * $s) (0.13 * $s)))
    $br.Dispose(); $pen.Dispose()
}

function New-CupImage([int]$size, $color) {
    $bmp = New-Object System.Drawing.Bitmap(($size + 6), ($size + 6))
    $gr = [System.Drawing.Graphics]::FromImage($bmp); $gr.SmoothingMode = 'AntiAlias'
    Draw-TrophyCup $gr 3 3 $size $color
    $gr.Dispose()
    return $bmp
}

function Get-XmlText($node, [string]$child) {
    # (SelectSingleNode: $node.name devolveria o nome do elemento, não o filho <name>)
    $n = $node.SelectSingleNode($child)
    if ($n) { return $n.InnerText.Trim() }
    return ''
}

function Get-TrophyConf([string]$file) {
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $null }
    try { $txt = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) } catch { return $null }
    # alguns arquivos têm assinatura ou bytes antes do XML: usa só o bloco <trophyconf>
    $a = $txt.IndexOf('<trophyconf'); $b = $txt.LastIndexOf('</trophyconf>')
    if ($a -lt 0 -or $b -lt $a) { return $null }
    try { return ([xml]$txt.Substring($a, $b - $a + 13)).DocumentElement } catch { return $null }
}

function New-TrophySet([string]$platform, [string]$key, [string]$title, [string]$icon) {
    return @{ platform = $platform; key = $key; title = $title; icon = $icon; trophies = New-Object System.Collections.ArrayList; last = [datetime]::MinValue }
}

# $unlocked: id -> data do desbloqueio ([datetime]::MinValue quando a data não é conhecida)
function Add-ConfTrophies($set, $conf, [hashtable]$unlocked, [string]$iconDir) {
    foreach ($t in $conf.SelectNodes('trophy')) {
        $id = [int]$t.GetAttribute('id')
        $earned = $unlocked.ContainsKey($id)
        $when = $null
        if ($earned -and $unlocked[$id] -ne [datetime]::MinValue) { $when = $unlocked[$id] }
        [void]$set.trophies.Add(@{
                id = $id; name = (Get-XmlText $t 'name'); detail = (Get-XmlText $t 'detail')
                grade = $t.GetAttribute('ttype').ToUpper(); hidden = ($t.GetAttribute('hidden') -eq 'yes')
                earned = $earned; time = $when; rarity = $null
                icon = (Join-Path $iconDir ('TROP{0:000}.PNG' -f $id))
            })
        if ($when -and $when -gt $set.last) { $set.last = $when }
    }
}

function Get-BigEndian([byte[]]$b, [int]$o, [int]$n) {
    $v = [decimal]0
    for ($i = 0; $i -lt $n; $i++) { $v = $v * 256 + $b[$o + $i] }
    return $v
}

function Read-Tropusr([string]$file) {
    # TROPUSR.DAT (big-endian): cabeçalho de 48 bytes e tabelas de 32; a tabela tipo 6 traz estado e data de cada troféu
    $res = @{}
    try { $b = [IO.File]::ReadAllBytes($file) } catch { return $res }
    if ($b.Length -lt 48 -or (Get-BigEndian $b 0 4) -ne 2173654189) { return $res }   # assinatura 81 8F 54 AD
    $tables = [int](Get-BigEndian $b 8 4)
    for ($t = 0; $t -lt $tables; $t++) {
        $h = 48 + $t * 32
        if ($h + 32 -gt $b.Length) { break }
        if ((Get-BigEndian $b $h 4) -ne 6) { continue }
        $count = [int](Get-BigEndian $b ($h + 12) 4); $off = [int64](Get-BigEndian $b ($h + 16) 8)
        for ($i = 0; $i -lt $count -and $off + 48 -le $b.Length; $i++) {
            if ((Get-BigEndian $b ($off + 20) 4) -ne 0) {
                # CellRtcTick: microssegundos desde 01/01/0001 (UTC)
                $tick = Get-BigEndian $b ($off + 32) 8
                $when = [datetime]::MinValue
                if ($tick -gt 0 -and $tick -lt 315537897599999999) { $when = [datetime]::new([int64]$tick * 10, [DateTimeKind]::Utc).ToLocalTime() }
                $res[[int](Get-BigEndian $b ($off + 16) 4)] = $when
            }
            $off += [math]::Max(16, [int](Get-BigEndian $b ($off + 4) 4) + 16)
        }
    }
    return $res
}

function Get-Ps3TrophySets {
    $sets = @()
    $exe = $script:Cfg.rpcs3
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $sets }
    $users = Join-Path (Split-Path $exe) 'dev_hdd0\home'
    foreach ($dir in (Get-ChildItem -Path (Join-Path $users '*\trophy\*') -Directory -ErrorAction SilentlyContinue)) {
        $conf = Get-TrophyConf (Join-Path $dir.FullName 'TROPCONF.SFM')
        if (-not $conf) { continue }
        $set = New-TrophySet 'PS3' "ps3:$($dir.Name)" (Get-XmlText $conf 'title-name') (Join-Path $dir.FullName 'ICON0.PNG')
        Add-ConfTrophies $set $conf (Read-Tropusr (Join-Path $dir.FullName 'TROPUSR.DAT')) $dir.FullName
        $sets += $set
    }
    return $sets
}

function ConvertFrom-TrophyStamp([string]$s) {
    # shadPS4 grava segundos desde 1970 (aceita também milissegundos e o tick do PS4, microssegundos desde o ano 1)
    $v = 0L
    if (-not [int64]::TryParse($s, [ref]$v) -or $v -le 0) { return [datetime]::MinValue }
    try {
        if ($v -gt 10000000000000000) { return [datetime]::new($v * 10, [DateTimeKind]::Utc).ToLocalTime() }
        if ($v -gt 100000000000) { return [DateTimeOffset]::FromUnixTimeMilliseconds($v).LocalDateTime }
        return [DateTimeOffset]::FromUnixTimeSeconds($v).LocalDateTime
    } catch { return [datetime]::MinValue }
}

function Add-XmlUnlocks([hashtable]$into, $conf) {
    if (-not $conf) { return }
    foreach ($t in $conf.SelectNodes('trophy')) {
        if ($t.GetAttribute('unlockstate') -ne 'true') { continue }
        $into[[int]$t.GetAttribute('id')] = ConvertFrom-TrophyStamp $t.GetAttribute('timestamp')
    }
}

function Get-Ps4TrophySets {
    $sets = @()
    $exe = $script:Cfg.shadps4
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $sets }
    $user = Join-Path (Split-Path $exe) 'user'
    $dirs = @(Get-ChildItem -LiteralPath (Join-Path $user 'trophy') -Directory -ErrorAction SilentlyContinue)
    # versões antigas do shadPS4: user\game_data\<CUSA>\TrophyFiles\trophy00 (desbloqueios dentro do próprio XML)
    $dirs += @(Get-ChildItem -Path (Join-Path $user 'game_data\*\TrophyFiles\*') -Directory -ErrorAction SilentlyContinue)
    $seen = @{}
    foreach ($dir in $dirs) {
        $xmlDir = Join-Path $dir.FullName 'Xml'
        # nomes em português do Brasil quando o jogo tem, senão o arquivo principal
        $file = @('TROP_17.XML', 'TROP_07.XML', 'TROP.XML') | ForEach-Object { Join-Path $xmlDir $_ } |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $conf = Get-TrophyConf $file
        if (-not $conf) { continue }
        $np = Get-XmlText $conf 'npcommid'
        if (-not $np) { $np = $dir.Name }
        if ($seen[$np]) { continue }
        $seen[$np] = $true
        $unlocked = @{}
        Add-XmlUnlocks $unlocked $conf
        if ((Split-Path $file -Leaf) -ne 'TROP.XML') { Add-XmlUnlocks $unlocked (Get-TrophyConf (Join-Path $xmlDir 'TROP.XML')) }
        foreach ($save in (Get-ChildItem -Path (Join-Path $user "home\*\trophy\$np.xml") -ErrorAction SilentlyContinue)) {
            Add-XmlUnlocks $unlocked (Get-TrophyConf $save.FullName)
        }
        $icons = Join-Path $dir.FullName 'Icons'
        $set = New-TrophySet 'PS4' "ps4:$np" (Get-XmlText $conf 'title-name') (Join-Path $icons 'ICON0.PNG')
        Add-ConfTrophies $set $conf $unlocked $icons
        $sets += $set
    }
    return $sets
}

# Conquistas do Trivium Hub: medidas pelo próprio launcher, então valem para todo jogo de qualquer console.
# secs: tempo total no jogo; run: tempo numa sessão; days: dias diferentes; all: todas as outras
$TriviumAch = @(
    @{ id = 'start'; name = 'Primeiro passo'; detail = 'Jogue por 1 minuto.'; grade = 'B'; secs = 60 }
    @{ id = 'h1'; name = 'Aquecendo'; detail = 'Jogue por 1 hora no total.'; grade = 'B'; secs = 3600 }
    @{ id = 'h5'; name = 'Pegando o jeito'; detail = 'Jogue por 5 horas no total.'; grade = 'B'; secs = 18000 }
    @{ id = 'd5'; name = 'De volta'; detail = 'Jogue em 5 dias diferentes.'; grade = 'B'; days = 5 }
    @{ id = 'h10'; name = 'Dedicação'; detail = 'Jogue por 10 horas no total.'; grade = 'S'; secs = 36000 }
    @{ id = 'h25'; name = 'Veterano'; detail = 'Jogue por 25 horas no total.'; grade = 'S'; secs = 90000 }
    @{ id = 'long'; name = 'Maratona'; detail = 'Jogue 2 horas seguidas.'; grade = 'S'; run = 7200 }
    @{ id = 'h50'; name = 'Lenda'; detail = 'Jogue por 50 horas no total.'; grade = 'G'; secs = 180000 }
    @{ id = 'd20'; name = 'Sempre por aqui'; detail = 'Jogue em 20 dias diferentes.'; grade = 'G'; days = 20 }
    @{ id = 'all'; name = 'Platina Trivium'; detail = 'Ganhe todas as outras conquistas deste jogo.'; grade = 'P'; all = $true }
)
$TriviumGrades = @{ P = 'Troféu de platina'; G = 'Troféu de ouro'; S = 'Troféu de prata'; B = 'Troféu de bronze' }

function Get-AchState {
    if ($script:AchState) { return $script:AchState }
    $script:AchState = @{}
    $file = Join-Path $TrophyDir 'trivium.json'
    if (Test-Path -LiteralPath $file) {
        try {
            foreach ($p in ([IO.File]::ReadAllText($file) | ConvertFrom-Json).PSObject.Properties) {
                $e = @{}; foreach ($x in $p.Value.earned.PSObject.Properties) { $e[$x.Name] = [string]$x.Value }
                $script:AchState[$p.Name] = @{ days = @($p.Value.days); earned = $e }
            }
        } catch { Write-AppLog "trivium.json: $($_.Exception.Message)" }
    }
    return $script:AchState
}

function Save-AchState {
    New-Item -ItemType Directory -Force $TrophyDir | Out-Null
    # grava ao lado e troca: se o PC desligar no meio, o progresso antigo fica inteiro
    $file = Join-Path $TrophyDir 'trivium.json'
    [IO.File]::WriteAllText("$file.tmp", ($script:AchState | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath "$file.tmp" $file -Force
}

function Test-RealTrophies($g) {
    # PS2 tem o RetroAchievements e jogo de PS4 com arquivo de troféus tem os reais: nada de conquistas Trivium neles
    if (-not $script:RealTrophyGames) { $script:RealTrophyGames = @{} }
    $k = ([string]$g.path).ToLower()
    if (-not $script:RealTrophyGames.ContainsKey($k)) {
        $kind = Get-ConsoleKind $g
        $script:RealTrophyGames[$k] = ($kind -eq 'PS2') -or (($kind -eq 'PS4') -and [bool](Get-Ps4TrpInfo $g))
    }
    return $script:RealTrophyGames[$k]
}

function Update-TriviumAch($g, [int]$session, [int]$unsaved) {
    # $session: segundos desta sessão; $unsaved: parte deles que ainda não entrou no tempo total. Devolve as novas
    if (Test-RealTrophies $g) { return @() }
    $all = Get-AchState
    $k = ([string]$g.path).ToLower()
    if (-not $all.ContainsKey($k)) { $all[$k] = @{ days = @(); earned = @{} } }
    $st = $all[$k]
    $changed = $false
    $today = (Get-Date).ToString('yyyy-MM-dd')
    if ($session -ge 60 -and $today -notin $st.days) { $st.days = @($st.days) + $today; $changed = $true }
    $secs = [int]$g.playSeconds + $unsaved
    $new = @()
    foreach ($a in $TriviumAch) {
        if ($a.all -or $st.earned.ContainsKey($a.id)) { continue }
        if (($a.secs -and $secs -ge $a.secs) -or ($a.run -and $session -ge $a.run) -or ($a.days -and @($st.days).Count -ge $a.days)) {
            $st.earned[$a.id] = (Get-Date).ToString('yyyy-MM-dd HH:mm'); $new += $a; $changed = $true
        }
    }
    $plat = $TriviumAch | Where-Object { $_.all }
    if (-not $st.earned.ContainsKey($plat.id) -and -not @($TriviumAch | Where-Object { -not $_.all -and -not $st.earned.ContainsKey($_.id) }).Count) {
        $st.earned[$plat.id] = (Get-Date).ToString('yyyy-MM-dd HH:mm'); $new += $plat; $changed = $true
    }
    if ($changed) { Save-AchState }
    return $new
}

function Get-TriviumTitle($g) { return ([string]$g.name -replace '\s*\[[^\]]*\]\s*$', '') }

function Get-TriviumCover($g) {
    if ($g.cover) { return Join-Path $CoverDir $g.cover }
    try {
        $key = $script:CoverKeys[$g.path]
        if (-not $key) { $key = Get-CoverKey $g }
        if ($key) { return Join-Path $CoverDir "$key.png" }
    } catch {}
    return $null
}

function Get-TrophySound([string]$grade) {
    # a platina tem som próprio
    $file = if ($grade -eq 'P') { 'platina.wav' } else { 'trofeu.wav' }
    return Join-Path (Join-Path $Root 'sons') $file
}

function Show-TriviumAlerts($g, $new) {
    $new = @($new | Where-Object { $_ })   # lista vazia chega aqui como $null
    if (-not $new.Count) { return }
    $h = [IntPtr]::Zero
    foreach ($p in (Get-RunProcs)) { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
    $title = Get-TriviumTitle $g
    $cover = Get-TriviumCover $g
    foreach ($a in @($new)) {
        if ($script:TrophyPopOk) { [PL.TrophyPop]::Enqueue((L $TriviumGrades[$a.grade]), (L $a.name), $title, $cover, $TrophyColors[$a.grade].ToArgb(), (Get-TrophySound $a.grade), $h) }
        else { Show-Toast "$(L 'Conquista'): $(L $a.name)" 'info' }
    }
}

function Get-Shadps4UserDir([string]$exe) {
    # sem a pasta user ao lado do exe, o shadPS4 usa a do Windows
    $user = Join-Path (Split-Path $exe) 'user'
    if (Test-Path -LiteralPath $user) { return $user }
    return Join-Path $env:APPDATA 'shadPS4'
}

function Test-Ps4TrophyKey([string]$exe) {
    if (-not $exe) { return $false }
    $path = Join-Path (Get-Shadps4UserDir $exe) 'keys.json'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try { return [bool]([IO.File]::ReadAllText($path) | ConvertFrom-Json).TrophyKeySet.ReleaseTrophyKey } catch { return $false }
}

function Export-TrpIcons([string]$trp, [string]$dir, [string]$listFile) {
    # só os textos do .trp são criptografados: as imagens dos troféus dá para ler sem a chave
    $fs = [IO.File]::OpenRead($trp)
    try {
        $head = New-Object byte[] 0x60
        if ($fs.Read($head, 0, 0x60) -ne 0x60 -or $head[0] -ne 0xDC -or $head[1] -ne 0xA2 -or $head[2] -ne 0x4D -or $head[3] -ne 0) { return }
        $count = [int](Get-BigEndian $head 16 4); $esz = [int](Get-BigEndian $head 20 4)
        if ($count -le 0 -or $count -gt 2000 -or $esz -lt 48) { return }
        $table = New-Object byte[] ($count * $esz)
        if ($fs.Read($table, 0, $table.Length) -ne $table.Length) { return }
        New-Item -ItemType Directory -Force $dir | Out-Null
        $ids = @()
        for ($i = 0; $i -lt $count; $i++) {
            $p = $i * $esz
            $name = [Text.Encoding]::ASCII.GetString($table, $p, 32).TrimEnd([char]0)
            if ($name -notmatch '^TROP(\d{3})\.PNG$') { continue }
            $id = [int]$Matches[1]
            $off = [long](Get-BigEndian $table ($p + 32) 8); $len = [long](Get-BigEndian $table ($p + 40) 8)
            if ($len -le 8 -or $len -gt 8MB -or $off + $len -gt $fs.Length) { continue }
            $png = New-Object byte[] $len
            $fs.Position = $off
            if ($fs.Read($png, 0, $png.Length) -ne $png.Length -or $png[0] -ne 0x89 -or $png[1] -ne 0x50) { continue }
            [IO.File]::WriteAllBytes((Join-Path $dir $name), $png)
            $ids += $id
        }
        if ($ids.Count) { [IO.File]::WriteAllLines($listFile, [string[]]($ids | Sort-Object)) }
    } finally { $fs.Dispose() }
}

function Get-Ps4TrpInfo($g) {
    # Combine não falha com um disco que não está mais conectado
    $sys = [IO.Path]::Combine([string]$g.path, 'sce_sys')
    $npb = [IO.Path]::Combine($sys, 'npbind.dat')
    if (-not (Test-Path -LiteralPath $npb)) { return $null }
    $m = [regex]::Match([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($npb)), 'NPWR\d{5}_\d{2}')
    if (-not $m.Success) { return $null }
    $dir = Join-Path $TrophyDir "ps4\$($m.Value)"
    $list = Join-Path $dir 'lista.txt'
    if (-not (Test-Path -LiteralPath $list)) {
        $trp = Get-ChildItem -LiteralPath (Join-Path $sys 'trophy') -Filter '*.trp' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $trp) { return $null }
        Export-TrpIcons $trp.FullName $dir $list
        if (-not (Test-Path -LiteralPath $list)) { return $null }
    }
    return @{ np = $m.Value; dir = $dir; ids = @([IO.File]::ReadAllLines($list) | ForEach-Object { [int]$_ }) }
}

function Get-SeenTrophies([string]$tid) {
    # id do troféu -> data em que o log mostrou o desbloqueio
    $res = @{}
    $file = Join-Path $TrophyDir 'ps4-trofeus.json'
    if (-not (Test-Path -LiteralPath $file)) { return $res }
    try {
        $node = ([IO.File]::ReadAllText($file) | ConvertFrom-Json).$tid
        if ($node) { foreach ($p in $node.PSObject.Properties) { $res[[int]$p.Name] = [string]$p.Value } }
    } catch { Write-AppLog "ps4-trofeus.json: $($_.Exception.Message)" }
    return $res
}

function Add-SeenTrophies([string]$tid, [int[]]$ids) {
    # o jogo pode pedir o mesmo troféu de novo a cada sessão: guarda os vistos e devolve só os novos
    $file = Join-Path $TrophyDir 'ps4-trofeus.json'
    $all = @{}
    if (Test-Path -LiteralPath $file) {
        try { foreach ($p in ([IO.File]::ReadAllText($file) | ConvertFrom-Json).PSObject.Properties) { $h = @{}; foreach ($x in $p.Value.PSObject.Properties) { $h[$x.Name] = [string]$x.Value }; $all[$p.Name] = $h } } catch { Write-AppLog "ps4-trofeus.json: $($_.Exception.Message)" }
    }
    if (-not $all.ContainsKey($tid)) { $all[$tid] = @{} }
    $new = @()
    foreach ($id in ($ids | Select-Object -Unique)) {
        if ($all[$tid].ContainsKey([string]$id)) { continue }
        $all[$tid][[string]$id] = (Get-Date).ToString('yyyy-MM-dd HH:mm'); $new += $id
    }
    if (-not $new.Count) { return @() }
    New-Item -ItemType Directory -Force $TrophyDir | Out-Null
    [IO.File]::WriteAllText("$file.tmp", ($all | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath "$file.tmp" $file -Force
    return $new
}

function Initialize-Ps4Memory($s) {
    # o shadPS4 reserva a memória do PS4 de uma vez ao abrir; sem espaço, fecha na hora (address_space.cpp).
    # A falha faz o Windows aumentar o arquivo de paginação, então vale esperar e pedir de novo antes de abrir
    if (-not $script:UiFreezeOk) { return }
    $gb = 14.0 + [int]$s.dmem / 1024
    for ($i = 0; $i -lt 5; $i++) {
        if ([PL.UiFreeze]::TryCommit($gb) -eq 0) { return }
        Start-Sleep -Milliseconds 800
    }
    Write-AppLog "Memória virtual insuficiente para reservar $gb GB antes de abrir o jogo"
    Show-Toast 'Pouca memória virtual: feche outros programas se o jogo não abrir' 'warn'
}

function Write-Ps4TrophyFiles([string]$exe, $g) {
    # sem a chave o shadPS4 não abre os troféus e alguns jogos desistem de avisar o desbloqueio. Com a lista já
    # baixada, grava os arquivos no formato que ele usaria; a pasta traz uma marca para nunca mexer numa extração real
    if (Test-Ps4TrophyKey $exe) { return }
    $info = Get-Ps4TrpInfo $g
    if (-not $info) { return }
    # jogo fora da lista pública ou ainda sem textos: grava assim mesmo, senão ele pode desistir dos troféus
    $texts = Get-Ps4TrophyTexts $info
    $user = Get-Shadps4UserDir $exe
    $base = [IO.Path]::Combine($user, 'trophy', $info.np)
    $mark = Join-Path $base 'trivium.txt'
    if ((Test-Path -LiteralPath $base) -and -not (Test-Path -LiteralPath $mark)) { return }
    $esc = { param($s) [Security.SecurityElement]::Escape([string]$s) }
    $title = & $esc (Get-TriviumTitle $g)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<trophyconf version=`"1.1`">`n<npcommid>$($info.np)</npcommid>`n<trophyset-version>01.00</trophyset-version>`n<parental-level license-area=`"default`">0</parental-level>`n<title-name>$title</title-name>`n<title-detail>$title</title-detail>`n")
    $hasPlat = @($texts.Values | Where-Object { $_.grade -eq 'P' }).Count -gt 0
    foreach ($id in $info.ids) {
        $x = $texts[[int]$id]
        $name = "$(L 'Troféu') $($id + 1)"; $det = ''; $grade = 'B'
        if ($x) { $grade = [string]$x.grade; $det = [string]$x.detail; if ($x.name) { $name = [string]$x.name } }
        $pid_ = '-1'; if ($hasPlat -and $grade -ne 'P') { $pid_ = '0' }
        [void]$sb.Append(('<trophy id="{0:000}" hidden="no" ttype="{1}" pid="{2}"><name>{3}</name><detail>{4}</detail></trophy>' -f $id, $grade, $pid_, (& $esc $name), (& $esc $det)) + "`n")
    }
    [void]$sb.Append("</trophyconf>`n")
    $utf8 = New-Object Text.UTF8Encoding($false)
    $xml = Join-Path $base 'Xml'; $icons = Join-Path $base 'Icons'
    New-Item -ItemType Directory -Force $xml, $icons | Out-Null
    [IO.File]::WriteAllText($mark, 'Gerado pelo Trivium Hub. Apague esta pasta para o shadPS4 voltar a usar o arquivo do jogo.', $utf8)
    foreach ($n in 'TROP.XML', 'TROPCONF.XML') { [IO.File]::WriteAllText((Join-Path $xml $n), $sb.ToString(), $utf8) }
    foreach ($id in $info.ids) { $f = 'TROP{0:000}.PNG' -f $id; Copy-Item -LiteralPath (Join-Path $info.dir $f) (Join-Path $icons $f) -Force }
    $ic = [IO.Path]::Combine([string]$g.path, 'sce_sys', 'icon0.png')
    if (Test-Path -LiteralPath $ic) { Copy-Item -LiteralPath $ic (Join-Path $icons 'ICON0.PNG') -Force }
    # o aviso do shadPS4 toca trophy.mp3 ou trophy.wav desta pasta, se existirem
    $sound = Join-Path $user 'custom_trophy'
    if (-not (Test-Path -LiteralPath (Join-Path $sound 'trophy.mp3')) -and -not (Test-Path -LiteralPath (Join-Path $sound 'trophy.wav'))) {
        New-Item -ItemType Directory -Force $sound | Out-Null
        Copy-Item -LiteralPath (Join-Path $Root 'sons\trofeu.wav') (Join-Path $sound 'trophy.wav') -Force
    }
    # o progresso de cada usuário fica aqui: só cria, nunca sobrescreve
    foreach ($uid in 1000, 1001, 1002, 1003) {
        $dir = [IO.Path]::Combine($user, 'home', "$uid", 'trophy')
        $save = Join-Path $dir "$($info.np).xml"
        if (Test-Path -LiteralPath $save) { continue }
        New-Item -ItemType Directory -Force $dir | Out-Null
        [IO.File]::WriteAllText($save, $sb.ToString(), $utf8)
    }
}

function Start-Ps4TrophyWatch([string]$exe, $g, [bool]$alert) {
    # só lê o log do shadPS4, que mostra o desbloqueio. Com os arquivos de troféu no lugar, quem avisa é o próprio
    # shadPS4, desenhando dentro do jogo; o cartão do launcher fica para jogo que ainda não tem esses arquivos
    $script:TrophyWatch = $null
    try {
        $tid = Get-Ps4TitleId $g.path
        if (-not $tid -or (Test-Ps4TrophyKey $exe)) { return }
        $log = Join-Path (Get-Shadps4UserDir $exe) 'log\shad_log.txt'
        $pos = [long]0
        if (Test-Path -LiteralPath $log) { $pos = (Get-Item -LiteralPath $log).Length }   # o log da sessão anterior não conta
        $info = Get-Ps4TrpInfo $g
        if ($info -and (Test-Path -LiteralPath ([IO.Path]::Combine((Get-Shadps4UserDir $exe), 'trophy', $info.np, 'Xml', 'TROP.XML')))) { $alert = $false }
        $script:TrophyWatch = @{ log = $log; pos = $pos; tail = ''; tid = $tid; alert = $alert; game = $g }
    } catch { Write-AppLog "Conquistas: $($_.Exception.Message)" }
}

function Get-NewTrophyIds($w) {
    # lê só o que entrou no log desde a última vez; o shadPS4 recomeça o arquivo a cada jogo
    try { $fs = [IO.File]::Open($w.log, 'Open', 'Read', 'ReadWrite, Delete') } catch { return @() }
    try {
        if ($fs.Length -lt $w.pos) { $w.pos = 0; $w.tail = '' }
        $n = [math]::Min($fs.Length - $w.pos, 8MB)
        if ($n -le 0) { return @() }
        $fs.Position = $w.pos
        $buf = New-Object byte[] $n
        $n = $fs.Read($buf, 0, $n)
        $w.pos += $n
    } finally { $fs.Dispose() }
    $txt = $w.tail + [Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $n)
    # linha ainda incompleta fica para a próxima leitura
    $cut = $txt.LastIndexOf("`n") + 1
    $w.tail = $txt.Substring($cut)
    return @([regex]::Matches($txt.Substring(0, $cut), 'Unlocking trophy id (\d+)') | ForEach-Object { [int]$_.Groups[1].Value })
}

# Nomes, descrições e tipos dos troféus de PS4: a lista pública do PSNine usa o mesmo número do NPWR do jogo e vem em
# chinês; o MyMemory traduz. Roda em segundo plano, uma vez por jogo, e nada disso vai no pacote do launcher.
$Ps4TextScript = {
    param([string]$np, [int]$count, [string]$dir, [string]$lang)
    $ua = 'TriviumHub/1.0 (launcher de jogos)'
    $file = Join-Path $dir "textos-$lang.json"
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
    $wc.Headers['User-Agent'] = $ua
    $html = $wc.DownloadString("https://www.psnine.com/psngame/$([int]$np.Substring(4, 5))")
    if ($html -notmatch $np) { return }
    $grades = @{ platinum = 'P'; gold = 'G'; silver = 'S'; bronze = 'B' }
    $rows = @()
    foreach ($part in ($html -split '<tr id="' | Select-Object -Skip 1)) {
        if ($part -notmatch '^(\d+)" class="trophy"') { continue }
        $id = [int]$Matches[1] - 1
        if ($part -notmatch 'class="text-(platinum|gold|silver|bronze)">([^<]*)</a>') { continue }
        $grade = $grades[$Matches[1]]; $name = [Net.WebUtility]::HtmlDecode($Matches[2]).Trim()
        $det = ''
        if ($part -match '</p>\s*<em[^>]*>([^<]*)') { $det = [Net.WebUtility]::HtmlDecode($Matches[1]).Trim() }
        $rows += [pscustomobject]@{ id = $id; grade = $grade; zh = $name; zhDetail = $det; name = ''; detail = '' }
    }
    # lista de outro tamanho: a numeração não é confiável, melhor manter "Troféu N"
    if ($rows.Count -ne $count) { return }
    if (Test-Path -LiteralPath $file) {
        try {
            $old = @{}; foreach ($o in ([IO.File]::ReadAllText($file) | ConvertFrom-Json)) { $old[[int]$o.id] = $o }
            foreach ($r in $rows) { if ($old[$r.id]) { $r.name = [string]$old[$r.id].name; $r.detail = [string]$old[$r.id].detail } }
        } catch {}
    }
    $tr = {
        param([string]$q)
        if (-not $q) { return '' }
        Start-Sleep -Milliseconds 250
        $wc.Headers['User-Agent'] = $ua
        $j = $wc.DownloadString('https://api.mymemory.translated.net/get?q=' + [Uri]::EscapeDataString($q) + "&langpair=zh-CN|$lang") | ConvertFrom-Json
        $t = [string]$j.responseData.translatedText
        if ([int]$j.responseStatus -ne 200 -or $t -match 'MYMEMORY WARNING') { throw 'limite de tradução' }
        return [Net.WebUtility]::HtmlDecode($t)
    }
    try {
        foreach ($r in $rows) {
            if (-not $r.name) { $r.name = & $tr $r.zh }
            if (-not $r.detail) { $r.detail = & $tr $r.zhDetail }
        }
    } catch {}
    finally {
        # o que faltar é retomado depois; os tipos reais já valem
        [IO.File]::WriteAllText("$file.tmp", (ConvertTo-Json @($rows) -Depth 3), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath "$file.tmp" $file -Force
    }
}

function Get-TrophyTextLang { if ((L 'Conquista') -ne 'Conquista') { return 'en-US' } return 'pt-BR' }

function Get-Ps4TrophyTexts($info) {
    # id -> grade, name, detail; vazio enquanto a lista não foi baixada
    $res = @{}
    $file = Join-Path $info.dir "textos-$(Get-TrophyTextLang).json"
    if (-not (Test-Path -LiteralPath $file)) { return $res }
    try { foreach ($o in ([IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $res[[int]$o.id] = $o } } catch { Write-AppLog "textos de troféus: $($_.Exception.Message)" }
    return $res
}

function Start-Ps4TextRefresh {
    # um jogo por vez e no máximo uma tentativa por abertura do launcher; com jogo aberto, espera
    if ($script:Ps4TextJob -or $script:RunDir) { return }
    if (-not $script:Ps4TextTried) { $script:Ps4TextTried = @{} }
    if (Test-Ps4TrophyKey $script:Cfg.shadps4) { return }
    foreach ($g in @($script:Cfg.games)) {
        if ((Get-ConsoleKind $g) -ne 'PS4' -or -not $g.path) { continue }
        $info = Get-Ps4TrpInfo $g
        if (-not $info -or $script:Ps4TextTried[$info.np]) { continue }
        $texts = Get-Ps4TrophyTexts $info
        if ($texts.Count -eq $info.ids.Count -and -not @($texts.Values | Where-Object { -not $_.name -or ($_.zhDetail -and -not $_.detail) }).Count) { continue }
        $script:Ps4TextTried[$info.np] = $true
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Ps4TextScript).AddArgument($info.np).AddArgument($info.ids.Count).AddArgument($info.dir).AddArgument((Get-TrophyTextLang))
        $script:Ps4TextJob = @{ ps = $ps; handle = $ps.BeginInvoke() }
        $ps4TextTimer.Start()
        return
    }
}

$ps4TextTimer = New-Object System.Windows.Forms.Timer
$ps4TextTimer.Interval = 500
$ps4TextTimer.Add_Tick({
        $j = $script:Ps4TextJob
        if (-not $j) { $ps4TextTimer.Stop(); return }
        if (-not $j.handle.IsCompleted) { return }
        $ps4TextTimer.Stop()
        $script:Ps4TextJob = $null
        try { [void]$j.ps.EndInvoke($j.handle) } catch { Write-AppLog "Nomes de troféus: $($_.Exception.Message)" }
        $j.ps.Dispose()
        try {
            if ($script:TrophyMode) { Update-TrophyData; Update-TrophyGames } else { Start-Ps4TextRefresh }
        } catch { Write-AppLog "Nomes de troféus: $($_.Exception.Message)" }
    })

function Update-Ps4TrophyWatch {
    $w = $script:TrophyWatch
    if (-not $w) { return }
    $ids = @(Get-NewTrophyIds $w)
    if (-not $ids.Count) { return }
    $new = @(Add-SeenTrophies $w.tid $ids)
    if (-not $new.Count) { return }
    $info = Get-Ps4TrpInfo $w.game
    $texts = @{}; if ($info) { $texts = Get-Ps4TrophyTexts $info }
    if (-not $w.alert) {
        # o aviso é o do shadPS4, que só tem um som: a platina toca o dela por aqui
        foreach ($id in $new) {
            $x = $texts[[int]$id]
            if ($x -and [string]$x.grade -eq 'P') {
                try { $script:PlatPlayer = New-Object System.Media.SoundPlayer((Get-TrophySound 'P')); $script:PlatPlayer.Play() } catch {}
            }
        }
        return
    }
    $h = [IntPtr]::Zero
    foreach ($p in (Get-RunProcs)) { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle; break } }
    foreach ($id in $new) {
        $img = Get-TriviumCover $w.game
        if ($info) { $ic = Join-Path $info.dir ('TROP{0:000}.PNG' -f $id); if (Test-Path -LiteralPath $ic) { $img = $ic } }
        $name = "$(L 'Troféu') $($id + 1)"; $grade = 'G'; $label = L 'Troféu do jogo'
        $x = $texts[[int]$id]
        if ($x) { $grade = [string]$x.grade; $label = L $TriviumGrades[$grade]; if ($x.name) { $name = [string]$x.name } }
        if ($script:TrophyPopOk) { [PL.TrophyPop]::Enqueue($label, $name, (Get-TriviumTitle $w.game), $img, $TrophyColors[$grade].ToArgb(), (Get-TrophySound $grade), $h) }
        else { Show-Toast "${label}: $name" 'info' }
    }
}

function Get-Ps4GameTrophySets {
    # troféus reais de cada jogo de PS4: quantidade e imagens vêm do jogo; nome, descrição e tipo, da lista baixada
    $sets = @()
    if (Test-Ps4TrophyKey $script:Cfg.shadps4) { return $sets }
    try {
        foreach ($g in @($script:Cfg.games)) {
            if ((Get-ConsoleKind $g) -ne 'PS4' -or -not $g.path) { continue }
            $info = Get-Ps4TrpInfo $g
            if (-not $info) { continue }
            $seen = Get-SeenTrophies (Get-Ps4TitleId $g.path)
            $texts = Get-Ps4TrophyTexts $info
            $set = New-TrophySet 'PS4' "ps4jogo:$($info.np)" (Get-TriviumTitle $g) (Get-TriviumCover $g)
            foreach ($id in $info.ids) {
                $earned = $seen.ContainsKey($id)
                $when = $null
                if ($earned) { try { $when = [datetime]::ParseExact($seen[$id], 'yyyy-MM-dd HH:mm', $null) } catch {} }
                $name = "$(L 'Troféu') $($id + 1)"; $det = 'Buscando o nome deste troféu...'; $grade = 'B'
                $x = $texts[[int]$id]
                if ($x) { $grade = [string]$x.grade; if ($x.name) { $name = [string]$x.name }; $det = [string]$x.detail }
                [void]$set.trophies.Add(@{ id = $id; name = $name; detail = $det; grade = $grade; hidden = $false; earned = $earned; time = $when; rarity = $null; icon = (Join-Path $info.dir ('TROP{0:000}.PNG' -f $id)) })
                if ($when -and $when -gt $set.last) { $set.last = $when }
            }
            $sets += $set
        }
    } catch { Write-AppLog "Conquistas: $($_.Exception.Message)" }
    return $sets
}

function Update-TriviumRun {
    # chamada pelo timer do jogo: nunca deixa um erro das conquistas chegar ao monitor do jogo
    try {
        Update-Ps4TrophyWatch
        $script:AchTicks++
        if ($script:RunMode -ne 'game' -or -not $script:RunGame -or $script:AchTicks % 10 -ne 0) { return }
        $run = [int]((Get-Date) - $script:RunStart).TotalSeconds
        Show-TriviumAlerts $script:RunGame (Update-TriviumAch $script:RunGame $run $run)
    } catch { Write-AppLog "Conquistas: $($_.Exception.Message)" }
}

function Add-TriviumTrophies($set, $g) {
    [void](Update-TriviumAch $g 0 0)
    $st = (Get-AchState)[([string]$g.path).ToLower()]
    foreach ($a in $TriviumAch) {
        $earned = $st.earned.ContainsKey($a.id)
        $when = $null
        if ($earned) { try { $when = [datetime]::ParseExact($st.earned[$a.id], 'yyyy-MM-dd HH:mm', $null) } catch {} }
        [void]$set.trophies.Add(@{ id = $a.id; name = $a.name; detail = $a.detail; grade = $a.grade; hidden = $false; earned = $earned; time = $when; rarity = $null; icon = $null })
        if ($when -and $when -gt $set.last) { $set.last = $when }
    }
}

function Get-TriviumTrophySets {
    $sets = @()
    try {
        foreach ($g in @($script:Cfg.games)) {
            if (-not $g.path -or (Test-RealTrophies $g)) { continue }
            $set = New-TrophySet (Get-ConsoleKind $g) "tr:$($g.path)" (Get-TriviumTitle $g) (Get-TriviumCover $g)
            Add-TriviumTrophies $set $g
            $sets += $set
        }
    } catch { Write-AppLog "Conquistas: $($_.Exception.Message)" }
    return $sets
}

function Get-RaAccount {
    $exe = $script:Cfg.pcsx2
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { return $null }
    $ini = Get-Pcsx2Ini $exe
    $a = Get-IniSection $ini 'Achievements'
    $tok = $a.Token
    # PCSX2 2.x guarda o token em secrets.ini, ao lado do PCSX2.ini
    if (-not $tok) { $tok = (Get-IniSection (Join-Path (Split-Path $ini) 'secrets.ini') 'Achievements').Token }
    if (-not $a.Username -or -not $tok) { return $null }
    return @{ user = $a.Username; token = $tok }
}

# roda em outro runspace (sem acesso às funções do launcher): devolve os jogos com conquistas da conta
$RaFetchScript = {
    param([string]$user, [string]$token, [int[]]$extraIds, [string]$dir)
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $call = {
        param($q)
        $wc = New-Object Net.WebClient
        $wc.Encoding = [Text.Encoding]::UTF8
        $wc.Headers['User-Agent'] = 'TriviumHub/1.0 (Windows)'
        $wc.Headers['Content-Type'] = 'application/x-www-form-urlencoded'
        $r = $wc.UploadString('https://retroachievements.org/dorequest.php', $q + '&u=' + [uri]::EscapeDataString($user) + '&t=' + [uri]::EscapeDataString($token)) | ConvertFrom-Json
        if (-not $r.Success) { throw ([string]$r.Error) }
        return $r
    }
    $fetchImg = {
        param($url, $file)
        if (-not $url -or (Test-Path -LiteralPath $file)) { return }
        try { (New-Object Net.WebClient).DownloadFile($url, "$file.part"); Move-Item -LiteralPath "$file.part" $file -Force } catch {}
    }
    $img = Join-Path $dir 'ra'
    New-Item -ItemType Directory -Force $img | Out-Null
    # jogos de PS2 (console 21) com alguma conquista + os que o PCSX2 reconheceu nos jogos da biblioteca
    $ids = @{}
    foreach ($p in (& $call 'r=allprogress&c=21').Response.PSObject.Properties) {
        if ([int]$p.Value.Unlocked + [int]$p.Value.UnlockedHardcore -gt 0) { $ids[[int]$p.Name] = $true }
    }
    foreach ($i in $extraIds) { if ($i -gt 0) { $ids[$i] = $true } }
    $games = @()
    foreach ($id in $ids.Keys) {
        $pd = (& $call "r=patch&g=$id").PatchData
        $soft = @((& $call "r=unlocks&g=$id&h=0").UserUnlocks)
        $hard = @((& $call "r=unlocks&g=$id&h=1").UserUnlocks)
        & $fetchImg $pd.ImageIconURL (Join-Path $img "game_$id.png")
        $list = @()
        foreach ($a in @($pd.Achievements)) {
            # só as oficiais (o ID enorme é o aviso "emulador desconhecido" do próprio site)
            if ([int]$a.Flags -ne 3 -or [int64]$a.ID -ge 100000000) { continue }
            & $fetchImg $a.BadgeURL (Join-Path $img "$($a.BadgeName).png")
            $list += [ordered]@{
                id = [int64]$a.ID; title = [string]$a.Title; desc = [string]$a.Description; points = [int]$a.Points
                badge = [string]$a.BadgeName; rarity = $a.Rarity
                earned = ($soft -contains $a.ID -or $hard -contains $a.ID); hardcore = ($hard -contains $a.ID)
            }
        }
        $games += [ordered]@{ id = $id; title = [string]$pd.Title; achievements = $list }
    }
    return $games
}

function Read-RaCache {
    $f = Join-Path $TrophyDir 'ra.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Save-RaCache($games) {
    # o site não informa a data pelo acesso do PCSX2: conta a partir de quando o launcher viu a conquista nova
    $old = Read-RaCache
    $prev = @{}; $known = @{}
    if ($old) {
        foreach ($og in @($old.games)) {
            $known["$($og.id)"] = $true
            foreach ($a in @($og.achievements)) { if ($a.earned) { $prev["$($a.id)"] = [string]$a.earnedAt } }
        }
    }
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    foreach ($g in $games) {
        foreach ($a in $g.achievements) {
            $a.earnedAt = ''
            if (-not $a.earned) { continue }
            if ($prev.ContainsKey("$($a.id)")) { $a.earnedAt = $prev["$($a.id)"] }
            elseif ($known["$($g.id)"]) { $a.earnedAt = $now }
        }
    }
    New-Item -ItemType Directory -Force $TrophyDir | Out-Null
    $json = [ordered]@{ updated = $now; games = @($games) } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText((Join-Path $TrophyDir 'ra.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-Ps2TrophySets {
    $sets = @()
    $c = Read-RaCache
    if (-not $c -or -not (Get-RaAccount)) { return $sets }
    $img = Join-Path $TrophyDir 'ra'
    foreach ($g in @($c.games)) {
        $set = New-TrophySet 'PS2' "ps2:$($g.id)" $g.title (Join-Path $img "game_$($g.id).png")
        $all = $true
        foreach ($a in @($g.achievements)) {
            $when = $null
            if ($a.earnedAt) { try { $when = [datetime]::ParseExact($a.earnedAt, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) } catch {} }
            # pontos do RetroAchievements viram tipo de troféu: 25+ ouro, 10+ prata, o resto bronze
            $grade = 'B'
            if ([int]$a.points -ge 25) { $grade = 'G' } elseif ([int]$a.points -ge 10) { $grade = 'S' }
            $rar = $null; if ($null -ne $a.rarity) { $rar = [double]$a.rarity }
            [void]$set.trophies.Add(@{
                    id = $a.id; name = $a.title; detail = $a.desc; grade = $grade; hidden = $false; points = [int]$a.points
                    earned = [bool]$a.earned; time = $when; rarity = $rar; icon = (Join-Path $img "$($a.badge).png")
                })
            if (-not $a.earned) { $all = $false }
            if ($when -and $when -gt $set.last) { $set.last = $when }
        }
        if ($set.trophies.Count) {
            # platina como no PS5: vem ao conquistar tudo (no RetroAchievements é o "domínio" do jogo)
            $pt = $null; if ($all -and $set.last -gt [datetime]::MinValue) { $pt = $set.last }
            $set.trophies.Insert(0, @{ id = -1; name = 'Mestre do jogo'; detail = "Conquiste todas as conquistas de $($g.title)."; grade = 'P'; hidden = $false; earned = $all; time = $pt; rarity = $null; icon = $set.icon })
        }
        $sets += $set
    }
    return $sets
}

function Update-TrophyStats($set) {
    $set.total = $set.trophies.Count; $set.earned = 0
    $set.counts = @{ P = 0; G = 0; S = 0; B = 0 }; $set.totals = @{ P = 0; G = 0; S = 0; B = 0 }
    foreach ($t in $set.trophies) {
        if (-not $set.totals.ContainsKey($t.grade)) { $t.grade = 'B' }
        $set.totals[$t.grade]++
        if ($t.earned) { $set.earned++; $set.counts[$t.grade]++ }
    }
    $set.pct = 0
    if ($set.total) { $set.pct = [int][math]::Floor(100 * $set.earned / $set.total) }
}

function Get-TrophyLevel([int]$pts) {
    # parecido com o PS5: 60 pontos por nível até o 99, 90 até o 199, 450 até o 299 e assim por diante
    $lvl = 1; $left = $pts
    foreach ($step in 60, 90, 450, 900, 1350, 1800, 2250, 2700, 3150, 3600) {
        $n = 100; if ($step -eq 60) { $n = 99 }
        for ($i = 0; $i -lt $n; $i++) {
            if ($left -lt $step) { return @{ level = $lvl; have = $left; need = $step } }
            $left -= $step; $lvl++
        }
    }
    return @{ level = 999; have = 1; need = 1 }
}

function Save-RaGameId($g, [string]$exe) {
    # o PCSX2 escreve no log qual jogo do RetroAchievements ele reconheceu: guarda para a aba Conquistas
    $log = Join-Path (Get-Pcsx2DataDir $exe) 'logs\emulog.txt'
    if (-not (Test-Path -LiteralPath $log)) { return }
    $m = [regex]::Matches((Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue), 'Identified game: (\d+)')
    if ($m.Count -eq 0) { return }
    $id = [int]$m[$m.Count - 1].Groups[1].Value
    if ([int]$g.raGameId -eq $id) { return }
    $g | Add-Member -NotePropertyName raGameId -NotePropertyValue $id -Force
    Save-Config
}

# ---------------------------------------------------------------- sobre e créditos
# os emuladores são de código aberto (GPL): a tela mostra a versão instalada, a licença e o código de cada um
$Credits = @(
    @{ name = 'PCSX2'; what = 'emulador de PS2'; lic = 'GPL-3.0'; dir = 'pcsx2'; ver = '.versao'; url = 'https://github.com/PCSX2/pcsx2' },
    @{ name = 'RPCS3'; what = 'emulador de PS3'; lic = 'GPL-2.0'; dir = 'rpcs3'; ver = '.versao'; url = 'https://github.com/RPCS3/rpcs3' },
    @{ name = 'shadPS4'; what = 'emulador de PS4'; lic = 'GPL-2.0'; dir = 'shadps4'; ver = '.versao'; url = 'https://github.com/shadps4-emu/shadPS4' },
    @{ name = 'shadPS4 eltutz'; what = 'de cuesta4, não oficial'; lic = 'GPL-2.0'; dir = 'shadps4'; ver = '.versao-shadps4eltutz'; url = 'https://github.com/cuesta4/shadPS4/tree/eltutz' },
    @{ name = 'PkgTool'; what = 'LibOrbisPkg, de maxton'; lic = 'LGPL-3.0'; dir = 'pkgtool'; ver = '.versao'; url = 'https://github.com/maxton/LibOrbisPkg' }
)

# ---------------------------------------------------------------- atualização do próprio launcher
# Procura a versão mais nova nas Releases do GitHub do Trivium Hub (tag "v1.2.0" com o arquivo "Trivium Hub.zip").
# Troca só os arquivos do launcher: jogos, saves, capas, configurações e emuladores ficam como estão
# (os emuladores se atualizam pelo "Instalar / atualizar todos").
$UpdateRepo = 'snowinglikee/trivium-hub'   # "usuario/repositorio" no GitHub onde as versões são publicadas; vazio = sem atualização automática
$UpdateFiles = @('Trivium Hub.exe', 'LEIA-ME.txt', 'README-EN.txt', 'app/Launcher.ps1', 'app/Instalar-Emuladores.ps1', 'app/icon.ico', 'app/licencas', 'app/idiomas', 'app/stub', 'app/sons')

function Compare-AppVersion([string]$a, [string]$b) {
    # >0 quando a é mais nova que b ("v1.2.0" x "1.1.9")
    $pa = @(($a -replace '^[vV]', '') -split '\.' | ForEach-Object { [int]("0$_" -replace '\D', '') })
    $pb = @(($b -replace '^[vV]', '') -split '\.' | ForEach-Object { [int]("0$_" -replace '\D', '') })
    for ($i = 0; $i -lt [math]::Max($pa.Count, $pb.Count); $i++) {
        $x = 0; if ($i -lt $pa.Count) { $x = $pa[$i] }
        $y = 0; if ($i -lt $pb.Count) { $y = $pb[$i] }
        if ($x -ne $y) { return $x - $y }
    }
    return 0
}

$UpdateCheckScript = {
    param([string]$repo)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'TriviumHub' } -TimeoutSec 15
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    return @{ tag = [string]$rel.tag_name; url = [string]$asset.browser_download_url; size = [int64]$asset.size; notes = [string]$rel.body }
}

function Start-UpdateCheck([bool]$manual = $false) {
    if (-not $UpdateRepo) {
        if ($manual) { Show-Toast 'Atualização automática ainda não configurada nesta cópia' 'info' }
        return
    }
    if ($script:UpdJob) { return }
    $ps = [powershell]::Create()
    [void]$ps.AddScript($UpdateCheckScript).AddArgument($UpdateRepo)
    $script:UpdJob = @{ ps = $ps; handle = $ps.BeginInvoke(); manual = $manual }
    $updTimer.Start()
}

$updTimer = New-Object System.Windows.Forms.Timer
$updTimer.Interval = 500
$updTimer.Add_Tick({
        $j = $script:UpdJob
        if (-not $j -or -not $j.handle.IsCompleted) { return }
        $updTimer.Stop(); $script:UpdJob = $null
        $r = $null
        try { $r = @($j.ps.EndInvoke($j.handle))[0] } catch {}
        $j.ps.Dispose()
        $script:Cfg.lastUpdateCheck = (Get-Date).ToString('yyyy-MM-dd'); Save-Config
        if (-not $r -or -not $r.tag) { if ($j.manual) { Show-Toast 'Não deu para procurar atualização (sem internet?)' 'warn' }; return }
        if ((Compare-AppVersion $r.tag $AppVersion) -le 0 -or -not $r.url) { if ($j.manual) { Show-Toast "Você já está na versão mais nova ($AppVersion)" 'ok' }; return }
        $script:UpdInfo = $r
        Show-Toast "Nova versão do Trivium Hub: $($r.tag)" 'info' 'Atualizar' { Install-AppUpdate $script:UpdInfo }
    })

function Install-AppUpdate($info) {
    if (-not $info) { return }
    if ($script:RunDir) { Show-Toast 'Feche o jogo antes de atualizar' 'warn'; return }
    $mb = [math]::Round($info.size / 1MB)
    $ok = [PL.Lang]::Msg("Atualizar o Trivium Hub para a versão $($info.tag)?`n`nDownload de $mb MB. Seus jogos, saves, capas e configurações continuam como estão.`nO launcher fecha e abre de novo sozinho.", 'Atualizar o Trivium Hub', 'YesNo')
    if ($ok -ne 'Yes') { return }
    $tmp = Join-Path $env:TEMP 'TriviumHub-update'
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp 'update.zip'
    Set-Status "Baixando a versão $($info.tag)..."; $form.Refresh()
    $form.Cursor = 'WaitCursor'
    & curl.exe -sL --fail -o $zip $info.url
    $code = $LASTEXITCODE
    if ($code -eq 0) { & tar.exe -xf $zip -C $tmp; $code = $LASTEXITCODE }
    $form.Cursor = 'Default'
    # o zip tem uma pasta "Trivium Hub" com o Trivium Hub.exe e a pasta app
    $src = Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'app\Launcher.ps1') } | Select-Object -First 1
    if ($code -ne 0 -or -not $src) { Show-Toast 'Falha ao baixar a atualização. Tente de novo mais tarde' 'warn'; Set-Status ''; return }
    $base = Split-Path $Root   # pasta do Trivium Hub.exe
    foreach ($f in $UpdateFiles) {
        $from = Join-Path $src.FullName $f
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $to = Join-Path $base $f
        if ((Get-Item -LiteralPath $from).PSIsContainer) { New-Item -ItemType Directory -Force $to | Out-Null; Copy-Item -Path (Join-Path $from '*') -Destination $to -Recurse -Force }
        else { Copy-Item -LiteralPath $from $to -Force }
    }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    # abre a versão nova e fecha esta
    $env:TRIVIUM_REOPEN = '1'
    Start-Process -FilePath (Join-Path $base 'Trivium Hub.exe') -WorkingDirectory $base
    $form.Close()
}

# ---------------------------------------------------------------- backup dos saves
# um .zip com os saves dos três consoles e a biblioteca (tempo jogado, favoritos, capas escolhidas).
# Backup automático uma vez por dia em app\cache\backups (guarda os 5 últimos).
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$BackupDir = Join-Path $Root 'cache\backups'

function Get-SaveSources {
    # caminhos relativos à pasta app (o zip guarda assim, para restaurar no mesmo lugar)
    $list = @('emuladores\pcsx2\memcards', 'emuladores\pcsx2\sstates', 'emuladores\rpcs3\dev_hdd0\home',
        'emuladores\shadps4\user\home', 'emuladores\shadps4\user\savedata', 'config.json', 'cache\conquistas\trivium.json', 'cache\conquistas\ps4-trofeus.json')
    foreach ($c in Get-ChildItem -LiteralPath $CoverDir -Filter 'custom_*' -File -ErrorAction SilentlyContinue) { $list += $c.FullName.Substring($Root.Length + 1) }
    return @($list | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) })
}

function New-SaveBackup([string]$zipPath) {
    Save-Config
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    New-Item -ItemType Directory -Force (Split-Path $zipPath) | Out-Null
    $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
    $n = 0
    try {
        foreach ($rel in Get-SaveSources) {
            $full = Join-Path $Root $rel
            $files = if ((Get-Item -LiteralPath $full).PSIsContainer) { Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue } else { Get-Item -LiteralPath $full }
            foreach ($f in $files) {
                $entry = $f.FullName.Substring($Root.Length + 1).Replace('\', '/')
                # arquivo aberto pelo emulador: copia por um stream que aceita compartilhamento
                $in = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
                try {
                    $out = $zip.CreateEntry($entry, 'Optimal').Open()
                    try { $in.CopyTo($out) } finally { $out.Dispose() }
                } finally { $in.Dispose() }
                $n++
            }
        }
    } finally { $zip.Dispose() }
    return $n
}

function Restore-SaveBackup([string]$zipPath) {
    if ($script:RunDir) { Show-Toast 'Feche o jogo antes de restaurar' 'warn'; return $false }
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($zip.Entries | Where-Object { $_.Name })
        # só aceita backup do Trivium Hub (caminhos de saves conhecidos, nada fora da pasta app)
        $ok = $entries.Count -gt 0 -and -not ($entries | Where-Object { $_.FullName -match '\.\.' -or $_.FullName -notmatch '^(emuladores/|config\.json$|covers/custom_|cache/conquistas/)' })
        if (-not $ok) { [void][PL.Lang]::Msg('Este arquivo não é um backup de saves do Trivium Hub.', 'Restaurar saves'); return $false }
        # antes de substituir, guarda os saves de agora
        [void](New-SaveBackup (Join-Path $BackupDir ("antes-de-restaurar_{0}.zip" -f (Get-Date).ToString('yyyy-MM-dd_HHmm'))))
        foreach ($en in $entries) {
            $dest = Join-Path $Root ($en.FullName.Replace('/', '\'))
            New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $dest, $true)
        }
    } finally { $zip.Dispose() }
    # a biblioteca do backup volta junto; os caminhos dos emuladores continuam os deste PC
    $emus = @{}; foreach ($k in $EmuKeys) { $emus[$k] = $script:Cfg[$k] }
    $script:Cfg = Load-Config
    foreach ($k in $EmuKeys) { if ($emus[$k]) { $script:Cfg[$k] = $emus[$k] } }
    $script:AchState = $null
    Save-Config
    Clear-CoverCache; Refresh-List
    return $true
}

function Invoke-AutoBackup {
    # um por dia, sem perguntar; apaga os mais antigos (fica com 5)
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $file = Join-Path $BackupDir "auto_$today.zip"
    if (Test-Path -LiteralPath $file) { return }
    try {
        [void](New-SaveBackup $file)
        Get-ChildItem -LiteralPath $BackupDir -Filter 'auto_*.zip' | Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Force
    } catch {}
}

function Show-SavesDialog {
    $d = New-Dialog 'Saves' 560 360
    $t = New-Label 'Backup dos saves' 20 14; $t.Font = $fontTitle
    $i = New-Label "Guarda num arquivo .zip os saves do PS2 (memory cards e save states), do PS3 e do PS4, os troféus e a sua biblioteca (tempo jogado, favoritos e capas escolhidas). Use para levar para outro PC ou se algo der errado.`n`nO launcher também faz um backup automático por dia (fica com os 5 últimos)." 22 50 $dim
    $i.MaximumSize = New-Object System.Drawing.Size(510, 0)
    $last = Get-ChildItem -LiteralPath $BackupDir -Filter 'auto_*.zip' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    $lt = 'Ainda não há backup automático.'
    if ($last) { $lt = "Último backup automático: $($last.LastWriteTime.ToString('dd/MM/yyyy HH:mm')) ($([math]::Round($last.Length / 1MB, 1)) MB)" }
    $l = New-Label $lt 22 186; $l.Font = $fontBold
    $bSave = New-Button 'Fazer backup agora...' 22 226 170 38
    $bSave.BackColor = $accent; $bSave.Font = $fontBold
    $bSave.Add_Click({
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Filter = L 'Backup do Trivium Hub|*.zip'; $dlg.FileName = "Trivium Hub - saves $((Get-Date).ToString('yyyy-MM-dd')).zip"
            $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $form.Cursor = 'WaitCursor'
            try { $n = New-SaveBackup $dlg.FileName; Show-Toast "Backup feito: $n arquivos" 'ok' }
            catch { [void][PL.Lang]::Msg("Não deu para fazer o backup:`n$($_.Exception.Message)", 'Saves') }
            $form.Cursor = 'Default'
        })
    $bLoad = New-Button 'Restaurar backup...' 200 226 160 38
    $bLoad.Add_Click({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = L 'Backup do Trivium Hub|*.zip'; $dlg.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
            if ($dlg.ShowDialog() -ne 'OK') { return }
            $r = [PL.Lang]::Msg("Os saves deste backup vão substituir os atuais.`nAntes disso, os saves de agora são guardados em app\cache\backups.`n`nContinuar?", 'Restaurar saves', 'YesNo')
            if ($r -ne 'Yes') { return }
            $form.Cursor = 'WaitCursor'
            try { if (Restore-SaveBackup $dlg.FileName) { Show-Toast 'Saves restaurados' 'ok' } }
            catch { [void][PL.Lang]::Msg("Não deu para restaurar:`n$($_.Exception.Message)", 'Saves') }
            $form.Cursor = 'Default'
        })
    $bDir = New-Button 'Backups automáticos' 368 226 168 38
    $bDir.Add_Click({ New-Item -ItemType Directory -Force $BackupDir | Out-Null; Start-Process explorer.exe -ArgumentList "`"$BackupDir`"" })
    $bClose = New-Button 'Fechar' 416 296 120 36; $bClose.DialogResult = 'OK'
    $d.Controls.AddRange(@($t, $i, $l, $bSave, $bLoad, $bDir, $bClose))
    $d.CancelButton = $bClose
    [void]$d.ShowDialog($form)
}

# ---------------------------------------------------------------- diagnóstico
# relatório do PC e da instalação, para conferir em outro computador ou mandar junto quando pedir ajuda
# (sem nome de usuário, senha, token ou caminho pessoal: a pasta do usuário vira %USERPROFILE%)
function Get-DiagnosticReport {
    $L = New-Object System.Collections.Generic.List[string]
    $hide = { param($p) if (-not $p) { return '' }; return ([string]$p).Replace($env:USERPROFILE, '%USERPROFILE%') }
    $L.Add("Trivium Hub $AppVersion  -  $((Get-Date).ToString('dd/MM/yyyy HH:mm'))")
    $L.Add("Pasta: $(& $hide (Split-Path $Root))")
    $L.Add('')
    $L.Add('== PC')
    try { $os = Get-CimInstance Win32_OperatingSystem; $L.Add("Windows: $($os.Caption) $($os.Version)  |  RAM: $([math]::Round($os.TotalVisibleMemorySize / 1MB, 1)) GB") } catch {}
    try { $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1; $L.Add("CPU: $($cpu.Name.Trim())  |  AVX2: $(if ([PL.Cpu]::HasAvx2()) { 'sim' } else { 'NÃO (shadPS4 eltutz não funciona)' })") } catch {}
    try { foreach ($v in Get-CimInstance Win32_VideoController) { $L.Add("GPU: $($v.Name)  |  driver $($v.DriverVersion)  |  $($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution) $($v.CurrentRefreshRate) Hz") } } catch {}
    $L.Add("Vulkan instalado: $(if (Test-Path (Join-Path $env:WINDIR 'System32\vulkan-1.dll')) { 'sim' } else { 'NÃO (atualize o driver da placa de vídeo)' })")
    try { $dr = Get-PSDrive ((Split-Path $Root -Qualifier).TrimEnd(':')); $L.Add("Espaço livre no disco: $([math]::Round($dr.Free / 1GB)) GB") } catch {}
    $L.Add('')
    $L.Add('== Emuladores')
    foreach ($k in $EmuKeys) {
        $exe = $script:Cfg[$k]
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $L.Add("$k : NÃO instalado"); continue }
        $vf = Join-Path (Split-Path $exe) '.versao'; $ver = '?'
        if (Test-Path -LiteralPath $vf) { $ver = (Get-Content -LiteralPath $vf -Raw).Trim() }
        $L.Add("$k : $ver")
    }
    if ($script:Cfg.shadps4) {
        $el = Join-Path (Split-Path $script:Cfg.shadps4) 'shadps4-eltutz.exe'
        $L.Add("shadps4 eltutz : $(if (Test-Path -LiteralPath $el) { 'instalado' } else { 'não instalado' })")
        $mods = Join-Path (Split-Path $script:Cfg.shadps4) 'user\sys_modules'
        $L.Add("módulos de firmware do PS4 (sys_modules): $(@(Get-ChildItem -LiteralPath $mods -File -ErrorAction SilentlyContinue).Count) arquivos")
    }
    # instalar PKG: o PkgTool precisa abrir (antivírus às vezes põe em quarentena)
    if (Get-PkgToolExe) {
        $pt = Test-PkgToolRuns
        $L.Add("PkgTool (instalar PKG): $(if ($pt) { "NÃO abre ($pt)" } else { 'ok' })")
    } else { $L.Add('PkgTool (instalar PKG): NÃO instalado') }
    $L.Add("Pasta de instalação de PS4: $(if ($script:Cfg.ps4InstallDir) { $script:Cfg.ps4InstallDir } else { '(ainda não escolhida)' })")
    $L.Add('')
    $L.Add('== BIOS / firmware')
    if ($script:Cfg.pcsx2) { $L.Add("BIOS do PS2: $(if (Test-Pcsx2Ready $script:Cfg.pcsx2) { 'ok' } else { 'FALTA' })") }
    if ($script:Cfg.rpcs3) { $L.Add("Firmware do PS3: $(if (Test-Path (Join-Path (Split-Path $script:Cfg.rpcs3) 'dev_flash\vsh\module\vsh.self')) { 'instalado' } else { 'FALTA' })") }
    $acc = Get-RaAccount
    $L.Add("RetroAchievements: $(if ($acc) { 'conectado' } else { 'não conectado' })")
    $L.Add('')
    $L.Add('== Biblioteca')
    $all = @($script:Cfg.games)
    foreach ($c in 'PS2', 'PS3', 'PS4') { $L.Add("$c : $(@($all | Where-Object { (Get-ConsoleKind $_) -eq $c }).Count) jogos") }
    $miss = @($all | Where-Object { -not (Test-Path -LiteralPath $_.path) })
    if ($miss.Count) { $L.Add("Arquivos que sumiram: $(($miss | ForEach-Object { $_.name }) -join '; ')") }
    foreach ($g in $all | Where-Object { (Get-ConsoleKind $_) -eq 'PS4' -and (Test-Path -LiteralPath $_.path) }) {
        $s = Get-GameSettings $g
        $L.Add("PS4 $($g.name): versão $(Get-Ps4AppVersion $g.path)$(if ($s.eltutz) { ', shadPS4 eltutz' })$(if ($s.textureFix) { ', patch de texturas' })$(if ($s.fps120) { ', 120 FPS' })")
    }
    $log = Join-Path $Root 'cache\erros.log'
    if (Test-Path -LiteralPath $log) {
        $L.Add('')
        $L.Add('== Últimos erros do launcher')
        foreach ($ln in (Get-Content -LiteralPath $log -Tail 15 -Encoding UTF8)) { $L.Add((& $hide $ln)) }
    }
    return (($L | ForEach-Object { L $_ }) -join "`r`n")
}

function Show-DiagnosticDialog {
    $d = New-Dialog 'Diagnóstico' 720 560
    $t = New-Label 'Diagnóstico do Trivium Hub' 20 14; $t.Font = $fontTitle
    $i = New-Label 'Confira se está tudo certo neste PC. Para pedir ajuda, clique em Copiar e cole a mensagem (não inclui senhas nem seu nome de usuário).' 22 46 $dim
    $i.MaximumSize = New-Object System.Drawing.Size(670, 0)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.WordWrap = $true
    $tb.Left = 22; $tb.Top = 92; $tb.Width = 670; $tb.Height = 360
    $tb.BackColor = $bg; $tb.ForeColor = $fg; $tb.BorderStyle = 'FixedSingle'; $tb.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $form.Cursor = 'WaitCursor'
    $tb.Text = Get-DiagnosticReport
    $form.Cursor = 'Default'
    $bCopy = New-Button 'Copiar' 22 470 120 36
    $bCopy.Tag = $tb
    $bCopy.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($this.Tag.Text); $this.Text = 'Copiado!' })
    $bClose = New-Button 'Fechar' 572 470 120 36; $bClose.DialogResult = 'OK'
    $d.Controls.AddRange(@($t, $i, $tb, $bCopy, $bClose))
    $d.CancelButton = $bClose
    $d.Tag = $bCopy
    $d.Add_Shown({ $this.Tag.Tag.SelectionLength = 0; [void]$this.Tag.Focus() })
    [void]$d.ShowDialog($form)
}

function Show-AboutDialog {
    $d = New-Dialog 'Sobre o Trivium Hub' 720 540
    # logo (app\logo.png, feita por stub\make-logo.ps1); sem ela, o nome em texto
    $logoFile = Join-Path $Root 'logo.png'
    if (Test-Path -LiteralPath $logoFile) {
        $t = New-Object System.Windows.Forms.PictureBox
        $t.Image = [System.Drawing.Image]::FromFile($logoFile)
        $t.SizeMode = 'Zoom'; $t.SetBounds(16, 12, 249, 66); $t.BackColor = [System.Drawing.Color]::Transparent
    } else { $t = New-Label 'Trivium Hub' 20 14; $t.Font = $fontTitle }
    $v = New-Label "Versão $AppVersion" 600 20 $dim
    $pitch = New-Label ('Seus jogos de PS2, PS3 e PS4 em um só lugar. Os emuladores já vêm dentro, cada jogo abre configurado e as correções da comunidade ' +
        '(patches de FPS, God of War III, Bloodborne) ligam sozinhas: nada de baixar um emulador ou um port diferente para cada jogo.') 22 90
    $pitch.MaximumSize = New-Object System.Drawing.Size(676, 0)
    $d.Controls.AddRange(@($t, $v, $pitch))
    $y = 90 + [math]::Max($pitch.Height, $pitch.PreferredHeight) + 14
    $i = New-Label 'Os jogos rodam nestes programas de código aberto, que vão junto sem modificação:' 22 $y $dim
    $i.MaximumSize = New-Object System.Drawing.Size(676, 0)
    $d.Controls.Add($i)
    $y += [math]::Max($i.Height, $i.PreferredHeight) + 14
    foreach ($c in $Credits) {
        $vf = Join-Path (Join-Path $EmuRoot $c.dir) $c.ver
        $ver = 'não instalado'
        if (Test-Path -LiteralPath $vf) { $ver = (Get-Content -LiteralPath $vf -Raw).Trim() -replace '^build-(\w{7})\w*$', 'build $1' -replace '^(shadps4-eltutz-|windows-)', '' -replace '^v\.', 'v' }
        $n = New-Label $c.name 22 $y; $n.Font = $fontBold
        $w = New-Label "$($c.what)  ·  $ver  ·  $($c.lic)" 160 ($y + 1) $dim
        $lk = New-Object System.Windows.Forms.LinkLabel
        $lk.Text = 'código-fonte'; $lk.Left = 604; $lk.Top = $y + 1; $lk.AutoSize = $true; $lk.Tag = $c.url
        $lk.LinkColor = [System.Drawing.Color]::FromArgb(130, 160, 255); $lk.ActiveLinkColor = $fg
        $lk.Add_LinkClicked({ Start-Process $this.Tag })
        $d.Controls.AddRange(@($n, $w, $lk))
        $y += 30
    }
    $y += 8
    $p = New-Label "Patches de PS4: comunidade do shadPS4, cuesta4 e kvicken. Conquistas do PS2: RetroAchievements.org. Capas de PS2: xlenore/ps2-covers.`nNão vêm no pacote: BIOS, firmware, chaves e jogos. PlayStation é marca da Sony; o Trivium Hub não tem ligação com a Sony nem com os autores dos emuladores." 22 $y $dim
    $p.MaximumSize = New-Object System.Drawing.Size(676, 0)
    $d.Controls.Add($p)
    # idioma e botões logo abaixo do texto (a altura da janela acompanha)
    $yl = $y + [math]::Max($p.Height, $p.PreferredHeight) + 22
    $yb = $yl + 38
    $bCred = New-Button 'Créditos completos' 22 $yb 152 36
    $bCred.Add_Click({ Start-Process notepad.exe -ArgumentList "`"$(Join-Path $Root 'licencas\CREDITOS.txt')`"" })
    $bLic = New-Button 'Licenças' 182 $yb 100 36
    $bLic.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$(Join-Path $Root 'licencas')`"" })
    $bDiag = New-Button 'Diagnóstico' 290 $yb 120 36
    $bDiag.Add_Click({ Show-DiagnosticDialog })
    $bUpd = New-Button 'Procurar atualização' 418 $yb 170 36
    $bUpd.Add_Click({ Start-UpdateCheck $true })
    $bUpd.Enabled = [bool]$UpdateRepo
    $bClose = New-Button 'Fechar' 596 $yb 100 36; $bClose.DialogResult = 'OK'
    $d.Controls.AddRange(@($bCred, $bLic, $bDiag, $bUpd, $bClose))
    # idioma do launcher (Language)
    $ll = New-Label 'Idioma / Language' 22 ($yl + 4); $ll.Font = $fontBold
    $cbl = New-Object System.Windows.Forms.ComboBox
    $cbl.DropDownStyle = 'DropDownList'; $cbl.Left = 180; $cbl.Top = $yl; $cbl.Width = 220
    $cbl.BackColor = $panelBg; $cbl.ForeColor = $fg; $cbl.FlatStyle = 'Flat'
    [void]$cbl.Items.AddRange(@('Automático (Windows) / Automatic', 'Português', 'English'))
    $cbl.SelectedIndex = [array]::IndexOf(@('auto', 'pt', 'en'), [string]$script:Cfg.lang)
    if ($cbl.SelectedIndex -lt 0) { $cbl.SelectedIndex = 0 }
    $cbl.Add_SelectedIndexChanged({
            $v = @('auto', 'pt', 'en')[$this.SelectedIndex]
            if ($v -eq $script:Cfg.lang) { return }
            $script:Cfg.lang = $v; Save-Config
            $r = [PL.Lang]::Msg('O idioma muda quando o Trivium Hub abrir de novo. Reabrir agora?', 'Trivium Hub', 'YesNo')
            if ($r -ne 'Yes') { return }
            $exe = Join-Path (Split-Path $Root) 'Trivium Hub.exe'
            $env:TRIVIUM_REOPEN = '1'
            if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $Root) }
            $this.FindForm().Close(); $form.Close()
        })
    $d.Controls.AddRange(@($ll, $cbl))
    $d.ClientSize = New-Object System.Drawing.Size($d.ClientSize.Width, ($yb + 54))
    $d.AcceptButton = $bClose; $d.CancelButton = $bClose
    [void]$d.ShowDialog($form)
}

function Install-Ps3Firmware {
    $exe = $script:Cfg.rpcs3
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { [void][PL.Lang]::Msg('Instale o RPCS3 primeiro.', 'Trivium Hub'); return }
    $r = [PL.Lang]::Msg(
        "Você já tem o arquivo PS3UPDAT.PUP?`n`nSim = escolher o arquivo e instalar`nNão = abrir o site oficial da Sony para baixar",
        'Firmware do PS3', 'YesNoCancel')
    if ($r -eq 'No') { Start-Process 'https://www.playstation.com/en-us/support/hardware/ps3/system-software/'; return }
    if ($r -ne 'Yes') { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = L 'Selecione PS3UPDAT.PUP'; $dlg.Filter = L 'Firmware PS3|PS3UPDAT.PUP;*.PUP'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    Start-Emu $exe @('--installfw', "`"$($dlg.FileName)`"") 'setup' $null
    Set-Status 'Instalando firmware do PS3 no RPCS3... feche o RPCS3 quando terminar.'
}

function Show-EmulatorsDialog {
    $d = New-Dialog 'Emuladores' 760 420
    $d.Controls.Add((New-Label 'Emuladores' 20 14))
    $d.Controls[0].Font = $fontTitle
    $d.Controls.Add((New-Label 'Instalados na pasta "emuladores" do launcher, baixados das páginas oficiais.' 22 44 $dim))

    $script:emuStatus = @{}
    $y = 84
    foreach ($k in $EmuKeys) {
        $lName = New-Label $EmuInfo[$k].label 22 ($y + 6)
        $lName.Font = $fontBold
        $lStat = New-Label '' 220 ($y + 6)
        $script:emuStatus[$k] = $lStat
        $bPick = New-Button 'Escolher .exe' 500 $y 120 32; $bPick.Tag = $k
        $bPick.Add_Click({ Pick-Emulator $this.Tag; Update-EmuStatus })
        $bOpen = New-Button 'Abrir' 628 $y 110 32; $bOpen.Tag = $k
        $bOpen.Add_Click({
                $exe = $script:Cfg[$this.Tag]
                if ($exe -and (Test-Path -LiteralPath $exe)) { Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) }
            })
        $d.Controls.AddRange(@($lName, $lStat, $bPick, $bOpen))
        $y += 44
    }

    $y += 16
    $bInstall = New-Button 'Instalar / atualizar todos' 22 $y 250 40
    $bInstall.BackColor = $accent; $bInstall.Font = $fontBold
    $bInstall.Add_Click({ Run-Installer $null; Update-EmuStatus })
    $bBios = New-Button 'BIOS do PS2...' 282 $y 150 40
    $bBios.Add_Click({ [void](Show-Ps2BiosDialog) })
    $bFw = New-Button 'Firmware do PS3...' 442 $y 170 40
    $bFw.Add_Click({ Install-Ps3Firmware })
    $bClose = New-Button 'Fechar' 622 $y 116 40
    $bClose.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($bInstall, $bBios, $bFw, $bClose))
    $d.CancelButton = $bClose
    $y += 56
    $tip = New-Label "A BIOS do PS2 e o firmware do PS3 não vêm junto: a BIOS sai do seu console e o firmware é gratuito no site da Sony." 22 $y $dim
    $tip.MaximumSize = New-Object System.Drawing.Size(716, 0)
    $d.Controls.Add($tip)
    $d.ClientSize = New-Object System.Drawing.Size(760, ($y + 50))

    Update-EmuStatus
    [void]$d.ShowDialog($form)
}

function Update-EmuStatus {
    if (-not $script:emuStatus) { return }
    foreach ($k in $EmuKeys) {
        $l = $script:emuStatus[$k]
        $v = Get-EmuVersion $k
        if ($v -match '^build-([0-9a-f]{7})') { $v = "build $($Matches[1])" }   # RPCS3 usa o hash do commit como versão
        if ($v) { $l.Text = "OK - $v"; $l.ForeColor = $okColor }
        else { $l.Text = 'não instalado'; $l.ForeColor = $badColor }
        $missing = $null
        if ($k -eq 'pcsx2' -and $v -and -not (Test-Pcsx2Ready $script:Cfg.pcsx2)) { $missing = 'falta BIOS' }
        if ($k -eq 'rpcs3' -and $v -and -not (Test-Path (Join-Path (Split-Path $script:Cfg.rpcs3) 'dev_flash\vsh\module\vsh.self'))) { $missing = 'falta firmware' }
        if ($missing) { $l.Text += "  ($missing)"; $l.ForeColor = [System.Drawing.Color]::FromArgb(255, 190, 90) }
    }
}

# ---------------------------------------------------------------- tela: o jogo fechou com erro

# configurações "seguras": as que menos dão problema, por console (por cima do Equilibrado)
$SafeOverrides = @{
    PS2 = @{ scale = 1; eeCycle = 0; mtvu = $false; fastCdvd = $false }
    PS3 = @{ scale = 100; spuBlock = 'Safe'; wcb = $false }
    PS4 = @{ screenMode = 'Fullscreen (Borderless)'; present = 'Fifo'; readbacks = 0; dmem = 0; fsr = $false; rcas = $false; neo = $false; copyBuffers = $false }
}

$CrashHints = @{
    PS2 = @(
        'Arquivo do jogo incompleto ou corrompido (baixe ou copie a ISO de novo).',
        'BIOS de outra região ou com problema: troque em Emuladores > BIOS do PS2.',
        'Configurações pesadas para o PC: tente as configurações seguras abaixo.',
        'Patch de FPS (60 FPS) instável neste jogo: as configurações seguras desligam.')
    PS3 = @(
        'Jogo ainda com problemas no RPCS3: veja a lista de compatibilidade.',
        'PKG da PSN sem a licença (.rap) na pasta dev_hdd0\home\00000001\exdata.',
        'Configurações que o jogo não aceita: tente as configurações seguras abaixo.')
    PS4 = @(
        'Patch de FPS (60 / 120 FPS) instável neste jogo: desmarque em Configurar (as configurações seguras desligam).',
        'Jogo ainda não roda no shadPS4: veja a lista de compatibilidade.',
        'Dump incompleto, ou atualização (patch) diferente da que o jogo precisa.',
        'Placa de vídeo sem Vulkan 1.3 ou driver antigo: atualize o driver.',
        'Opções que o jogo não aceita: tente as configurações seguras abaixo.')
}

function Get-EmuLogTail([string]$exe, [datetime]$since) {
    # últimas linhas de erro do log do emulador desta sessão (vazio se o log é velho)
    $leaf = (Split-Path $exe -Leaf).ToLower()
    $dir = Split-Path $exe
    $file = $null; $pat = $null
    switch -Wildcard ($leaf) {
        'pcsx2*' { $file = Join-Path (Get-Pcsx2DataDir $exe) 'logs\emulog.txt'; $pat = '(?i)\b(fatal|error|exception|failed|crash)' }
        'rpcs3*' { $file = Join-Path $dir 'RPCS3.log'; $pat = '(^|·)[FE] |(?i)\bfatal\b' }
        'shadps4*' { $file = Join-Path $dir 'user\log\shad_log.txt'; $pat = '<Critical>' }
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return $null }
    $fi = Get-Item -LiteralPath $file
    if ($fi.LastWriteTime -lt $since.AddSeconds(-5)) { return $null }
    $tail = @(Get-Content -LiteralPath $file -Tail 800 -ErrorAction SilentlyContinue)
    $hits = @($tail | Where-Object { $_ -match $pat })
    # shadPS4: sem linha crítica, usa os erros comuns
    if (-not $hits.Count -and $leaf -like 'shadps4*') { $hits = @($tail | Where-Object { $_ -match '<Error>' }) }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($h in $hits) {
        $line = $h.Trim()
        if ($line.Length -gt 220) { $line = $line.Substring(0, 220) + '...' }
        # mesma mensagem repetida: fica só a mais recente
        [void]$out.Remove($line); $out.Add($line)
    }
    if ($out.Count -eq 0) { foreach ($l in ($tail | Select-Object -Last 4)) { $out.Add($l.Trim()) } }
    return @{ path = $file; lines = @($out | Select-Object -Last 6) }
}

function Set-SafeSettings($g) {
    $kind = Get-ConsoleKind $g
    $h = Get-GameSettings $g
    foreach ($k in $Presets[$kind]['Equilibrado'].Keys) { $h[$k] = $Presets[$kind]['Equilibrado'][$k] }
    foreach ($k in $SafeOverrides[$kind].Keys) { $h[$k] = $SafeOverrides[$kind][$k] }
    $fix = Get-GameFix $g
    if ($fix) { foreach ($k in $fix.Keys) { $h[$k] = $fix[$k] } }
    # patches de FPS mexem no tempo do jogo inteiro e são os que mais fecham jogo: o modo seguro desliga
    foreach ($k in $OwnPatchOptions) { $h[$k] = $false }
    $h.preset = 'Personalizado'
    $o = [ordered]@{}
    foreach ($k in $h.Keys) { $o[$k] = $h[$k] }
    $g | Add-Member -NotePropertyName settings -NotePropertyValue ([pscustomobject]$o) -Force
    Save-Config
}

function Show-CrashDialog($g, [string]$exe, $code, [int]$secs, [datetime]$since) {
    $kind = Get-ConsoleKind $g
    $emu = switch -Wildcard ((Split-Path $exe -Leaf).ToLower()) { 'pcsx2*' { 'PCSX2' } 'rpcs3*' { 'RPCS3' } 'shadps4-eltutz*' { 'shadPS4 eltutz' } default { 'shadPS4' } }
    $d = New-Dialog 'O jogo fechou' 660 520
    $ic = New-Object System.Windows.Forms.PictureBox
    $ic.SetBounds(24, 20, 44, 44); $ic.SizeMode = 'CenterImage'
    $ic.Image = New-GlyphImage 0xE7BA 30 ([System.Drawing.Color]::FromArgb(255, 170, 90))
    $title = if ($code -ne 0) { 'O jogo fechou com um erro' } else { 'O jogo fechou logo depois de abrir' }
    $lt = New-Label $title 78 20; $lt.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
    $codeTxt = "aberto por $secs s"
    if ($code -ne 0) {
        # códigos de falha do Windows mais comuns, em palavras
        $hex = '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$code), 0)
        $known = @{ '0xC0000005' = 'falha de memória'; '0xC0000409' = 'erro interno do emulador'; '0xC000001D' = 'instrução que a CPU não tem'; '0xC00000FD' = 'estouro de pilha'; '0xC0000374' = 'memória corrompida' }
        $codeTxt = "erro $hex"
        if ($known.ContainsKey($hex)) { $codeTxt += " ($(L $known[$hex]))" }
    }
    $ls = New-Label "$($g.name)  •  $emu  •  $codeTxt" 80 52 $dim
    $d.Controls.AddRange(@($ic, $lt, $ls))

    $y = 92
    $lh = New-Label 'O que pode ser' 24 $y; $lh.Font = $fontBold
    $d.Controls.Add($lh); $y += 26
    # o aviso do patch de FPS só aparece quando o jogo estava com um ligado
    $gs = Get-GameSettings $g
    $fpsOn = [bool]($gs.fps60 -or $gs.fps120)
    if ($kind -eq 'PS2' -and $fpsOn) { $fpsOn = [bool](Get-Ps2FpsPatch $g $exe) }
    foreach ($hint in @($CrashHints[$kind] | Where-Object { $fpsOn -or $_ -notlike 'Patch de FPS*' })) {
        $l = New-Label ([string][char]0x2022 + '  ' + $hint) 30 $y $fg
        $l.MaximumSize = New-Object System.Drawing.Size(600, 0)
        $d.Controls.Add($l)
        $y += [System.Windows.Forms.TextRenderer]::MeasureText($l.Text, $l.Font, (New-Object System.Drawing.Size(600, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height + 6
    }
    if ($code -eq 0) {
        $l = New-Label 'Se foi você que fechou o jogo, pode ignorar este aviso.' 30 ($y + 2) $dim
        $d.Controls.Add($l); $y += 26
    }

    $log = Get-EmuLogTail $exe $since
    $script:CrashLogPath = $null
    if ($log) {
        $script:CrashLogPath = $log.path
        $y += 8
        $ll = New-Label "Últimas mensagens de erro do $emu" 24 $y; $ll.Font = $fontBold
        $d.Controls.Add($ll); $y += 26
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.WordWrap = $true
        $tb.SetBounds(24, $y, 612, 110)
        $tb.BackColor = [System.Drawing.Color]::FromArgb(16, 16, 20); $tb.ForeColor = [System.Drawing.Color]::FromArgb(210, 210, 220)
        $tb.BorderStyle = 'FixedSingle'; $tb.Font = New-Object System.Drawing.Font('Consolas', 8.5)
        $tb.Text = ($log.lines -join "`r`n"); $tb.TabStop = $false
        $d.Controls.Add($tb); $y += 120
    }

    $y += 10
    $bSafe = New-Button 'Tentar com configurações seguras' 24 $y 270 42
    $bSafe.BackColor = $accent; $bSafe.Font = $fontBold; $bSafe.FlatAppearance.BorderSize = 0; $bSafe.Cursor = 'Hand'
    $bSafe.DialogResult = 'Retry'
    $d.Controls.Add($bSafe)
    $x = 304
    if ($script:CrashLogPath) {
        $bLog = New-Button 'Abrir log' $x $y 110 42; $bLog.Cursor = 'Hand'
        $bLog.Add_Click({ Start-Process notepad.exe "`"$($script:CrashLogPath)`"" })
        $d.Controls.Add($bLog); $x += 118
    }
    if ($kind -ne 'PS2') {
        $script:CrashCompatUrl = if ($kind -eq 'PS3') { 'https://rpcs3.net/compatibility?g=' + [uri]::EscapeDataString((Get-Ps3TitleId $g)) }
        else { 'https://github.com/shadps4-emu/shadps4-game-compatibility/issues?q=' + [uri]::EscapeDataString("$(Get-Ps4TitleId $g.path)") }
        $bComp = New-Button 'Compatibilidade' $x $y 130 42; $bComp.Cursor = 'Hand'
        $bComp.Add_Click({ Start-Process $script:CrashCompatUrl })
        $d.Controls.Add($bComp); $x += 138
    }
    $bClose = New-Button 'Fechar' $x $y (636 - $x) 42; $bClose.DialogResult = 'Cancel'
    $d.Controls.Add($bClose); $d.CancelButton = $bClose
    $y += 54
    $note = New-Label 'Configurações seguras: resolução normal, opções mais compatíveis e sem patch de FPS. Dá para mudar depois em Configurar.' 24 $y $dim
    $note.Font = New-Object System.Drawing.Font('Segoe UI', 8.5); $note.MaximumSize = New-Object System.Drawing.Size(612, 0)
    $d.Controls.Add($note)
    $d.ClientSize = New-Object System.Drawing.Size(660, ($y + 36))
    $d.ActiveControl = $bSafe

    if ($d.ShowDialog($form) -eq 'Retry') {
        Set-SafeSettings $g
        Refresh-List; [void](Select-Game $g)
        Show-Toast 'Configurações seguras aplicadas. Abrindo de novo...' 'info'
        Start-Game $g
    }
}

# ---------------------------------------------------------------- tela: primeiros passos

function Get-SetupSteps {
    # cada passo: feito ou não, e o texto de situação
    $installed = @('pcsx2', 'rpcs3', 'shadps4' | Where-Object { $script:Cfg[$_] -and (Test-Path -LiteralPath $script:Cfg[$_]) })
    $pcsx2 = $script:Cfg.pcsx2; $rpcs3 = $script:Cfg.rpcs3
    $bios = $pcsx2 -and (Test-Path -LiteralPath $pcsx2) -and (Test-Pcsx2Ready $pcsx2)
    $fw = $rpcs3 -and (Test-Path -LiteralPath $rpcs3) -and (Test-Path (Join-Path (Split-Path $rpcs3) 'dev_flash\vsh\module\vsh.self'))
    $games = @($script:Cfg.games).Count
    return [ordered]@{
        emus  = @{ done = $installed.Count -eq 3; status = "$($installed.Count) de 3 instalados" }
        bios  = @{ done = [bool]$bios; status = $(if ($bios) { 'BIOS configurada' } else { 'falta a BIOS' }) }
        fw    = @{ done = [bool]$fw; status = $(if ($fw) { 'firmware instalado' } else { 'falta o firmware' }) }
        games = @{ done = $games -gt 0; status = $(if ($games -eq 1) { '1 jogo na biblioteca' } elseif ($games) { "$games jogos na biblioteca" } else { 'nenhum jogo ainda' }) }
    }
}

function Show-SetupAssistant {
    $d = New-Dialog 'Primeiros passos' 680 620
    [System.Windows.Forms.Form].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($d, $true, $null)
    if ($form.Visible) { $d.StartPosition = 'CenterParent' } else { $d.StartPosition = 'CenterScreen' }
    $t = New-Label 'Bem-vindo ao Trivium Hub' 28 20; $t.Font = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
    $sub = New-Label 'Faça estes passos uma vez. Depois é só escolher o jogo e jogar.' 30 60 $dim
    $d.Controls.AddRange(@($t, $sub))

    $defs = @(
        @{ key = 'emus'; title = 'Emuladores'; tag = ''; desc = 'PCSX2 (PS2), RPCS3 (PS3) e shadPS4 (PS4), baixados dos sites oficiais.'; btn = 'Instalar'; btnDone = 'Atualizar'; act = { Run-Installer $null } }
        @{ key = 'bios'; title = 'BIOS do PS2'; tag = 'só para PS2'; desc = 'Copiada do seu próprio PS2 (arquivo .bin de cerca de 4 MB).'; btn = 'Escolher BIOS...'; btnDone = 'Trocar BIOS...'; act = { [void](Show-Ps2BiosDialog) } }
        @{ key = 'fw'; title = 'Firmware do PS3'; tag = 'só para PS3'; desc = 'Gratuito no site oficial da Sony (arquivo PS3UPDAT.PUP).'; btn = 'Instalar firmware...'; btnDone = 'Reinstalar...'; act = { Install-Ps3Firmware } }
        @{ key = 'games'; title = 'Seus jogos'; tag = ''; desc = 'ISO, PKG ou a pasta do jogo. Também dá para arrastar para a janela.'; btn = 'Adicionar jogos...'; btnDone = 'Adicionar mais...'; act = { Invoke-AddFiles } }
    )
    $script:SetupRows = [ordered]@{}
    $y = 100; $n = 1
    foreach ($s in $defs) {
        $row = New-Object System.Windows.Forms.Panel
        $row.SetBounds(28, $y, 624, 88); $row.BackColor = $panelBg
        $row.Region = New-Object System.Drawing.Region((New-RoundRect 0 0 624 88 10))
        $row.Tag = @{ n = $n; done = $false }
        $row.Add_Paint({
                $pg = $_.Graphics; $pg.SmoothingMode = 'AntiAlias'; $pg.TextRenderingHint = 'AntiAliasGridFit'
                $st = $this.Tag
                if ($st.done) {
                    $pg.FillEllipse((New-Object System.Drawing.SolidBrush($okColor)), 18, 26, 36, 36)
                    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
                    $pg.DrawString([string][char]0xE73E, (New-Object System.Drawing.Font($IconFont, 14)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(20, 40, 25))), (New-Object System.Drawing.RectangleF(18, 27, 36, 36)), $sf)
                } else {
                    $pg.DrawEllipse((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 110, 125), 2)), 19, 27, 34, 34)
                    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
                    $pg.DrawString((L ([string]$st.n)), $fontBold, (New-Object System.Drawing.SolidBrush($fg)), (New-Object System.Drawing.RectangleF(18, 27, 36, 36)), $sf)
                }
            })
        $lt = New-Label $s.title 72 12; $lt.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold); $lt.BackColor = $panelBg
        $row.Controls.Add($lt)
        if ($s.tag) {
            $ltag = New-Label $s.tag 0 15 $dim; $ltag.Font = New-Object System.Drawing.Font('Segoe UI', 8.5); $ltag.BackColor = $panelBg
            $ltag.Left = 72 + [System.Windows.Forms.TextRenderer]::MeasureText($s.title, $lt.Font).Width + 4
            $row.Controls.Add($ltag)
        }
        $ld = New-Label $s.desc 72 36 $dim; $ld.BackColor = $panelBg; $ld.MaximumSize = New-Object System.Drawing.Size(360, 0); $ld.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        # situação logo abaixo da descrição (que pode ter 1 ou 2 linhas)
        $dh = [System.Windows.Forms.TextRenderer]::MeasureText($s.desc, $ld.Font, (New-Object System.Drawing.Size(360, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height
        $ls = New-Label '' 72 (36 + $dh + 2); $ls.BackColor = $panelBg; $ls.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        $row.Controls.AddRange(@($ld, $ls))
        $b = $null
        if ($s.btn) {
            $b = New-Button $s.btn 448 26 160 36
            $b.Cursor = 'Hand'; $b.Tag = $s.act
            $b.Add_Click({ & $this.Tag; Update-SetupAssistant })
            $row.Controls.Add($b)
        }
        $d.Controls.Add($row)
        $script:SetupRows[$s.key] = @{ row = $row; status = $ls; button = $b; def = $s }
        $y += 96; $n++
    }

    $script:SetupProgress = New-Label '' 30 ($y + 14) $dim
    $script:SetupProgress.Font = $fontBold
    $script:SetupShow = New-Object System.Windows.Forms.CheckBox
    $script:SetupShow.Text = 'Mostrar esta tela ao abrir o launcher'; $script:SetupShow.AutoSize = $true
    $script:SetupShow.Left = 30; $script:SetupShow.Top = $y + 40; $script:SetupShow.ForeColor = $dim
    $bGo = New-Button 'Começar a jogar' 452 ($y + 18) 200 44
    $bGo.BackColor = $accent; $bGo.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $bGo.FlatAppearance.BorderSize = 0; $bGo.Cursor = 'Hand'; $bGo.DialogResult = 'OK'
    $d.Controls.AddRange(@($script:SetupProgress, $script:SetupShow, $bGo))
    $d.AcceptButton = $bGo
    $d.ClientSize = New-Object System.Drawing.Size(680, ($y + 80))

    [void](Update-SetupAssistant)
    # volta a abrir sozinha só enquanto faltar o básico (BIOS e firmware dependem do console que a pessoa joga)
    $steps = Get-SetupSteps
    $script:SetupShow.Checked = -not ($steps.emus.done -and $steps.games.done)
    # o firmware muda por fora (instalado pelo RPCS3): confere de tempos em tempos
    $st = New-Object System.Windows.Forms.Timer
    $st.Interval = 1500
    $st.Add_Tick({ [void](Update-SetupAssistant) })
    $st.Start()
    $d.Add_Activated({ [void](Update-SetupAssistant) })
    [void]$d.ShowDialog($form)
    $st.Stop(); $st.Dispose()
    $script:Cfg.showWelcome = $script:SetupShow.Checked
    Save-Config
    $script:SetupRows = $null
}

function Update-SetupAssistant {
    # atualiza os passos; retorna $true quando os obrigatórios estão feitos
    if (-not $script:SetupRows) { return $false }
    $steps = Get-SetupSteps
    $doneCount = 0
    foreach ($k in $script:SetupRows.Keys) {
        $r = $script:SetupRows[$k]; $s = $steps[$k]
        if ($r.row.Tag.done -ne $s.done) { $r.row.Tag.done = $s.done; $r.row.Invalidate() }
        $r.status.Text = $s.status
        if ($s.done) { $r.status.ForeColor = $okColor } else { $r.status.ForeColor = [System.Drawing.Color]::FromArgb(255, 190, 90) }
        if ($r.button) {
            if ($s.done) { $r.button.Text = $r.def.btnDone; $r.button.BackColor = $panelBg; $r.button.Font = $font }
            else { $r.button.Text = $r.def.btn; $r.button.BackColor = $accent; $r.button.Font = $fontBold }
        }
        if ($s.done) { $doneCount++ }
    }
    $script:SetupProgress.Text = "$doneCount de 4 passos feitos"
    if ($doneCount -eq 4) { $script:SetupProgress.Text += ' - tudo pronto!'; $script:SetupProgress.ForeColor = $okColor }
    else { $script:SetupProgress.ForeColor = $dim }
    return ($doneCount -eq 4)
}

function Pick-Emulator([string]$which) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = L $EmuInfo[$which].title
    $dlg.Filter = L $EmuInfo[$which].filter
    if ($dlg.ShowDialog() -eq 'OK') {
        $script:Cfg[$which] = $dlg.FileName
        Save-Config
    }
}

# ---------------------------------------------------------------- janela principal

$script:Cfg = Load-Config
# pacote portátil: os emuladores embutidos são procurados de novo a cada início,
# então a pasta pode ser movida ou copiada para outro PC
Update-EmuPaths $true
# o launcher foi fechado no meio de um jogo com saturação NVIDIA: devolve as cores normais
if ($script:Cfg.restoreVibrance) { Restore-Vibrance }

$form = New-Object System.Windows.Forms.Form
[PL.Dark]::Use($form)
$form.Text = 'Trivium Hub'
$form.Size = New-Object System.Drawing.Size(1300, 720)
$form.MinimumSize = New-Object System.Drawing.Size(1080, 460)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $bg; $form.ForeColor = $fg; $form.Font = $font
$form.AllowDrop = $true
# volta com o tamanho e a posição da última vez (se ainda couber em algum monitor)
if ($script:Cfg.windowBounds -match '^(-?\d+),(-?\d+),(\d+),(\d+)$') {
    $wb = New-Object System.Drawing.Rectangle([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4])
    $onScreen = $false
    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) { if ($scr.WorkingArea.IntersectsWith($wb)) { $onScreen = $true } }
    if ($onScreen -and $wb.Width -ge $form.MinimumSize.Width -and $wb.Height -ge $form.MinimumSize.Height) {
        $form.StartPosition = 'Manual'; $form.Bounds = $wb
    }
}
if ($script:Cfg.windowMax) { $form.WindowState = 'Maximized' }
$iconPath = Join-Path $Root 'icon.ico'
if (Test-Path $iconPath) { try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch {} }

# ---- barra de cima: botões com ícone (fonte de ícones do Windows, Segoe MDL2) e busca grande
$IconFont = 'Segoe MDL2 Assets'
$Glyph = @{ tv = 0xE7F4; play = 0xE768; settings = 0xE713; add = 0xE710; folder = 0xE8F4; remove = 0xE74D; emus = 0xE7FC; trophy = 0xE734; star = 0xE735; search = 0xE721; grid = 0xE80A; list = 0xEA37 }

function New-GlyphImage([int]$code, [int]$size = 16, $color = $fg) {
    $px = $size + 6
    $bmp = New-Object System.Drawing.Bitmap($px, $px)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.TextRenderingHint = 'AntiAliasGridFit'
    $f = New-Object System.Drawing.Font($IconFont, $size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $gr.DrawString([string][char]$code, $f, (New-Object System.Drawing.SolidBrush($color)), (New-Object System.Drawing.RectangleF(0, 1, $px, $px)), $sf)
    $gr.Dispose()
    return $bmp
}

function New-TopButton([string]$text, [string]$iconName, [bool]$primary = $false) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "  $(L $text)"; $b.Height = 40
    $b.Font = if ($primary) { $fontBold } else { $font }
    $b.Image = New-GlyphImage $Glyph[$iconName] 16 $fg
    $b.TextImageRelation = 'ImageBeforeText'; $b.ImageAlign = 'MiddleCenter'; $b.TextAlign = 'MiddleCenter'
    $b.Width = [System.Windows.Forms.TextRenderer]::MeasureText($b.Text, $b.Font).Width + 42
    $b.FlatStyle = 'Flat'; $b.ForeColor = $fg; $b.Cursor = 'Hand'
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    if ($primary) {
        $b.BackColor = $accent; $b.FlatAppearance.BorderSize = 0
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(95, 135, 245)
    } else {
        $b.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 52)
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(62, 62, 74)
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
    }
    return $b
}

$top = New-Object System.Windows.Forms.Panel
$top.Dock = 'Top'; $top.Height = 62; $top.BackColor = $panelBg

$btnPlay = New-TopButton 'JOGAR' 'play' $true
$btnSettings = New-TopButton 'Configurar' 'settings'
$btnAddFile = New-TopButton 'Adicionar jogo' 'add'
$btnAddDir = New-TopButton 'Adicionar pasta' 'folder'
$btnRemove = New-TopButton 'Remover' 'remove'
$btnEmus = New-TopButton 'Emuladores' 'emus'
$btnAch = New-TopButton 'Conquistas' 'trophy'
$btnAch.Image = New-CupImage 15 $fg
# (os botões acima continuam existindo para atalhos e dicas; a barra mostra só o essencial:
#  jogar, configurar e remover ficam no painel do jogo e no botão direito; conquistas é uma aba)

# ---- barra de cima: marca à esquerda, busca no meio, Adicionar / Modo TV / mais opções à direita
$brand = New-Object System.Windows.Forms.Panel
$brand.Dock = 'Left'; $brand.Width = 210; $brand.BackColor = $panelBg
[System.Windows.Forms.Panel].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($brand, $true, $null)
$fontBrand = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$fontBrandSub = New-Object System.Drawing.Font('Segoe UI', 8.5)
$brand.Add_Paint({
        $gr = $_.Graphics; $gr.SmoothingMode = 'AntiAlias'; $gr.TextRenderingHint = 'ClearTypeGridFit'
        # a mesma marca do ícone: o T de três caminhos
        if ($script:PlayFxOk) { [PL.Emblem]::Draw($gr, 33, 27, 37) }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, 'TRIVIUM HUB', $fontBrand, (New-Object System.Drawing.Point(58, 11)), $fg)
        [System.Windows.Forms.TextRenderer]::DrawText($gr, 'PS2  ·  PS3  ·  PS4', $fontBrandSub, (New-Object System.Drawing.Point(60, 35)), $dim)
    })
$brand.Add_Click({ Set-ConsoleFilter 'Todos' })

$btnAdd = New-TopButton 'Adicionar' 'add' $true
$btnAdd.Text += '  ' + [char]0x25BE
$btnAdd.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnAdd.Text, $btnAdd.Font).Width + 42
$btnTvTop = New-TopButton 'Modo TV' 'tv'
$btnMore = New-Object System.Windows.Forms.Button
$btnMore.Size = New-Object System.Drawing.Size(42, 40); $btnMore.FlatStyle = 'Flat'; $btnMore.Cursor = 'Hand'
$btnMore.Image = New-GlyphImage 0xE712 16 $fg
$btnMore.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 52)
$btnMore.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(62, 62, 74)
$btnMore.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnMore.Margin = New-Object System.Windows.Forms.Padding(0)
$topFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$topFlow.Dock = 'Right'; $topFlow.WrapContents = $false; $topFlow.BackColor = $panelBg
$topFlow.AutoSize = $true; $topFlow.AutoSizeMode = 'GrowAndShrink'
$topFlow.Padding = New-Object System.Windows.Forms.Padding(0, 11, 14, 0)
$topFlow.Controls.AddRange(@($btnAdd, $btnTvTop, $btnMore))

function Show-TopMenu($btn, $items) {
    # menu escuro embaixo do botão; item = @(texto, ícone, ação, atalho) ou '-' para separador
    $m = New-Object System.Windows.Forms.ContextMenuStrip
    $m.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object PL.DarkMenuColors))
    $m.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 48); $m.ForeColor = $fg
    $m.Font = New-Object System.Drawing.Font('Segoe UI', 10); $m.ImageScalingSize = New-Object System.Drawing.Size(20, 20)
    foreach ($it in $items) {
        if ($it -eq '-') { [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)); continue }
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($it[0])
        $mi.Image = $it[1]; $mi.ForeColor = $fg; $mi.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
        if ($it[3]) { $mi.ShortcutKeyDisplayString = $it[3] }
        $mi.Add_Click($it[2])
        [void]$m.Items.Add($mi)
    }
    [PL.Lang]::HookMenu($m)
    $m.Show($btn, (New-Object System.Drawing.Point($btn.Width, ($btn.Height + 4))), [System.Windows.Forms.ToolStripDropDownDirection]::BelowLeft)
}

$btnAdd.Add_Click({
        Show-TopMenu $this @(
            @('Adicionar jogos...', (New-GlyphImage $Glyph.add 14 $fg), { Invoke-AddFiles }, ''),
            @('Adicionar pasta...', (New-GlyphImage $Glyph.folder 14 $fg), { Invoke-AddFolder }, ''),
            '-',
            @('Instalar PKG de PS4...', (New-GlyphImage 0xE896 14 $fg), { Invoke-InstallPkgDialog }, '')
        )
    })
$btnTvTop.Add_Click({ Show-TvMode })
$btnMore.Add_Click({
        Show-TopMenu $this @(
            @('Emuladores', (New-GlyphImage $Glyph.emus 14 $fg), { Show-EmulatorsDialog }, ''),
            @('Conquistas', (New-CupImage 13 $fg), { Show-TrophyView }, 'Ctrl+6'),
            @('Saves (backup)', (New-GlyphImage 0xE74E 14 $fg), { Show-SavesDialog }, ''),
            '-',
            @('Primeiros passos', (New-GlyphImage 0xE897 14 $fg), { Show-SetupAssistant; Refresh-List }, 'F1'),
            @('Sobre e créditos', (New-GlyphImage 0xE946 14 $fg), { Show-AboutDialog }, '')
        )
    })

# busca: caixa escura com lupa e texto de ajuda ("Buscar jogo...")
$searchHost = New-Object System.Windows.Forms.Panel
$searchHost.Dock = 'Right'; $searchHost.Width = 270; $searchHost.BackColor = $panelBg
$searchHost.Padding = New-Object System.Windows.Forms.Padding(0, 11, 14, 11)
$searchBox = New-Object System.Windows.Forms.Panel
$searchBox.Dock = 'Fill'; $searchBox.BackColor = $bg
$searchBox.Padding = New-Object System.Windows.Forms.Padding(8, 1, 8, 1)   # 1 px em cima e embaixo: a lupa não cobre a borda
$searchBox.Add_Paint({
        $r = $this.ClientRectangle; $r.Width -= 1; $r.Height -= 1
        $c = if ($txtSearch.Focused) { $accent } else { [System.Drawing.Color]::FromArgb(62, 62, 74) }
        $_.Graphics.DrawRectangle((New-Object System.Drawing.Pen($c)), $r)
    })
$searchIcon = New-Object System.Windows.Forms.PictureBox
$searchIcon.Dock = 'Left'; $searchIcon.Width = 26; $searchIcon.SizeMode = 'CenterImage'; $searchIcon.BackColor = $bg
$searchIcon.Image = New-GlyphImage $Glyph.search 15 $dim
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.BorderStyle = 'None'; $txtSearch.BackColor = $bg; $txtSearch.ForeColor = $fg
$txtSearch.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$txtSearch.Anchor = 'Left, Right'
$searchBox.Controls.Add($txtSearch)
$searchBox.Controls.Add($searchIcon)
# centraliza o texto na altura da caixa (TextBox sem borda não centraliza sozinho)
$script:LayoutSearch = {
    $txtSearch.Left = $searchIcon.Right + 4; $txtSearch.Width = $searchBox.ClientSize.Width - $txtSearch.Left - 8
    $txtSearch.Top = [int](($searchBox.ClientSize.Height - $txtSearch.Height) / 2)
}
$searchBox.Add_Resize({ & $script:LayoutSearch })
$txtSearch.Add_GotFocus({ $searchBox.Invalidate() })
$txtSearch.Add_LostFocus({ $searchBox.Invalidate() })
$searchBox.Add_Click({ [void]$txtSearch.Focus() })
$searchIcon.Add_Click({ [void]$txtSearch.Focus() })
$searchHost.Controls.Add($searchBox)
Add-Type -Namespace PL -Name Cue -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);'

$searchHost.Dock = 'Fill'
$top.Controls.Add($searchHost)
$top.Controls.Add($brand)
$top.Controls.Add($topFlow)
# a busca fica no meio, com no máximo 520 px de largura
$top.Add_Resize({
        $free = $this.ClientSize.Width - $brand.Width - $topFlow.Width
        $side = [math]::Max(8, [int](($free - 520) / 2))
        $searchHost.Padding = New-Object System.Windows.Forms.Padding($side, 11, $side, 11)
    })

$lv = New-Object System.Windows.Forms.ListView
$lv.Dock = 'Fill'; $lv.View = 'LargeIcon'; $lv.FullRowSelect = $true; $lv.MultiSelect = $false
$lv.BackColor = $bg; $lv.ForeColor = $fg; $lv.BorderStyle = 'None'; $lv.HideSelection = $false
[void]$lv.Columns.Add((L 'Jogo'), 400)
[void]$lv.Columns.Add('Console', 100)
[void]$lv.Columns.Add((L 'Predefinição'), 190)
[void]$lv.Columns.Add((L 'Arquivo'), 380)
# coluna do arquivo ocupa o que sobra (sem barra de rolagem de lado com o painel do jogo aberto)
$script:FitColumns = {
    if ($lv.View -ne 'Details') { return }
    $lv.Columns[0].Width = [math]::Max(220, [math]::Min(400, [int]($lv.ClientSize.Width * 0.42)))
    $rest = $lv.ClientSize.Width - $lv.Columns[0].Width - $lv.Columns[1].Width - $lv.Columns[2].Width - 4
    $lv.Columns[3].Width = [math]::Max(120, $rest)
}
$lv.Add_Resize({ & $script:FitColumns })

# capas ao lado do nome (a altura da linha acompanha a altura da imagem)
$imgCovers = New-Object System.Windows.Forms.ImageList
$imgCovers.ColorDepth = 'Depth32Bit'
$imgCovers.ImageSize = New-Object System.Drawing.Size($CoverW, $CoverH)
$lv.SmallImageList = $imgCovers
$imgGrid = New-Object System.Windows.Forms.ImageList
$imgGrid.ColorDepth = 'Depth32Bit'
$imgGrid.ImageSize = New-Object System.Drawing.Size($GridW, $GridH)
$lv.LargeImageList = $imgGrid
Add-Type -Namespace PL -Name Lv -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);'

function Set-LibraryView([string]$mode) {
    # grade = capas grandes estilo biblioteca; lista = detalhes com capa pequena
    $script:ViewMode = $mode
    # grade desenhada pelo launcher (cantos arredondados, destaque ao passar o mouse); lista no padrão do Windows
    $lv.OwnerDraw = $mode -ne 'lista'
    $script:HotIndex = -1
    if ($mode -eq 'lista') {
        $lv.View = 'Details'
        $lv.Columns[1].Width = 90; $lv.Columns[2].Width = 130
        & $script:FitColumns
        $btnView.Text = '  Ver em grade'; $btnView.Image = New-GlyphImage $Glyph.grid 14 $fg
        $btnSize.Visible = $false
    } else {
        $lv.View = 'LargeIcon'
        # espaço entre as capas (LVM_SETICONSPACING): largura e altura de cada bloco, com o nome embaixo
        [void][PL.Lv]::SendMessage($lv.Handle, 0x1035, [IntPtr]::Zero, [IntPtr](($GridH + 56) * 65536 + ($GridW + 26)))
        $btnView.Text = '  Ver em lista'; $btnView.Image = New-GlyphImage $Glyph.list 14 $fg
        $btnSize.Visible = $true
    }
    Refresh-List
}

# ---- cartões da grade: capa com cantos arredondados, sombra, destaque ao passar o mouse e anel na cor de destaque no escolhido
# sem piscar ao redesenhar (DoubleBuffered é protegido no ListView)
[System.Windows.Forms.ListView].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($lv, $true, $null)
$CardH = $GridH + 56     # altura de cada bloco da grade (mesma do espaçamento)

# ---- tamanho das capas na grade (Pequeno / Médio / Grande; também Ctrl + rodinha do mouse)
$CoverSizes = [ordered]@{ pequeno = @('Pequeno', 120, 160); medio = @('Médio', 150, 200); grande = @('Grande', 186, 248) }
$script:CoverSize = 'medio'

function Set-CoverSize([string]$size, [bool]$refresh = $true) {
    if (-not $CoverSizes.Contains($size)) { $size = 'medio' }
    $script:CoverSize = $size
    $sz = $CoverSizes[$size]
    $script:GridW = $sz[1]; $script:GridH = $sz[2]; $script:CardH = $sz[2] + 56
    # as duas listas de imagens andam juntas (Get-CoverImageKey confere as duas): limpa e refaz no tamanho novo
    $imgCovers.Images.Clear(); $imgGrid.Images.Clear()
    $imgGrid.ImageSize = New-Object System.Drawing.Size($sz[1], $sz[2])
    $btnSize.Text = '  ' + (L "Capas: $($sz[0])")
    $btnSize.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnSize.Text, $btnSize.Font).Width + 40
    if ($refresh) {
        $script:DetailCovers.Clear()
        if ($script:ViewMode -ne 'lista') { [void][PL.Lv]::SendMessage($lv.Handle, 0x1035, [IntPtr]::Zero, [IntPtr](($GridH + 56) * 65536 + ($GridW + 26))) }
        Refresh-List
        $lv.Invalidate()
    }
}

function Step-CoverSize([int]$step) {
    $keys = @($CoverSizes.Keys)
    $i = [math]::Max(0, [math]::Min($keys.Count - 1, [array]::IndexOf($keys, $script:CoverSize) + $step))
    if ($keys[$i] -eq $script:CoverSize) { return }
    Set-CoverSize $keys[$i]
    $script:Cfg.coverSize = $keys[$i]; Save-Config
}

function Show-SizeMenu {
    # (criado na hora: as cores escuras do menu, PL.DarkMenuColors, são definidas mais abaixo no arquivo)
    if (-not $script:SizeMenu) {
        $m = New-Object System.Windows.Forms.ContextMenuStrip
        $m.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object PL.DarkMenuColors))
        $m.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 48); $m.ForeColor = $fg
        $m.Font = New-Object System.Drawing.Font('Segoe UI', 10); $m.ShowImageMargin = $false; $m.ShowCheckMargin = $true
        foreach ($k in $CoverSizes.Keys) {
            $mi = New-Object System.Windows.Forms.ToolStripMenuItem($CoverSizes[$k][0])
            $mi.Tag = $k; $mi.ForeColor = $fg; $mi.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
            $mi.Add_Click({ Set-CoverSize $this.Tag; $script:Cfg.coverSize = $this.Tag; Save-Config })
            [void]$m.Items.Add($mi)
        }
        $script:SizeMenu = $m
        [PL.Lang]::HookMenu($m)
    }
    foreach ($mi in $script:SizeMenu.Items) { $mi.Checked = ($mi.Tag -eq $script:CoverSize) }
    # abre para cima: o botão fica na barra de baixo
    $script:SizeMenu.Show($btnSize, (New-Object System.Drawing.Point(0, 0)), [System.Windows.Forms.ToolStripDropDownDirection]::AboveRight)
}

# Ctrl + rodinha em cima da grade muda o tamanho
$lv.Add_MouseWheel({
        if (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -eq 0 -or $script:ViewMode -eq 'lista') { return }
        if ($_.Delta -gt 0) { Step-CoverSize 1 } else { Step-CoverSize -1 }
        if ($_ -is [System.Windows.Forms.HandledMouseEventArgs]) { $_.Handled = $true }
    })
$fontCard = New-Object System.Drawing.Font('Segoe UI', 9.5)
$fontCardSel = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$fontStar = New-Object System.Drawing.Font('Segoe MDL2 Assets', 10)
$fontBadge = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)

function Test-NewGame($g) {
    if (-not $g -or $g.lastPlayed -or -not $g.added) { return $false }
    try { return ((Get-Date) - [datetime]::ParseExact([string]$g.added, 'yyyy-MM-dd HH:mm:ss', $null)).TotalDays -lt 7 } catch { return $false }
}
$script:HotIndex = -1

function New-RoundRect([single]$x, [single]$y, [single]$rw, [single]$rh, [single]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $rad * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $rw - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $rw - $d, $y + $rh - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $rh - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# ---- fundo da biblioteca: a arte do jogo escolhido (como na tela inicial do PS5)
# PS4: sce_sys\pic1.png (a imagem de fundo do próprio jogo); PS3: PIC1.PNG; PS2 e o resto: a capa bem desfocada
$script:LibBack = $null
$script:LibBackCache = @{}

function Get-GameArtFile($g) {
    $kind = Get-ConsoleKind $g
    $cands = @()
    if ($kind -eq 'PS4' -and $g.console -eq 'PS4') {
        foreach ($d in "$($g.path)-UPDATE", $g.path) { $cands += (Join-Path $d 'sce_sys\pic1.png'), (Join-Path $d 'sce_sys\pic0.png') }
    } elseif ($kind -eq 'PS3') {
        $base = $g.path
        if ($base -like '*EBOOT.BIN') { $base = Split-Path (Split-Path $base) }   # ...\PS3_GAME\USRDIR\EBOOT.BIN -> PS3_GAME
        elseif (Test-Path -LiteralPath (Join-Path $base 'PS3_GAME')) { $base = Join-Path $base 'PS3_GAME' }
        $cands += (Join-Path $base 'PIC1.PNG'), (Join-Path $base 'PIC0.PNG')
    }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

function New-LibBackdrop($g, [int]$w, [int]$h) {
    $art = Get-GameArtFile $g
    $key = "$($g.path)|$w|$h"
    if ($script:LibBackCache.ContainsKey($key)) { return $script:LibBackCache[$key] }
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    $gr.Clear($bg)
    $gr.InterpolationMode = 'HighQualityBicubic'
    $src = $null
    if ($art) { try { $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($art)); $src = [System.Drawing.Image]::FromStream($ms) } catch {} }
    if ($src) {
        # arte do jogo: preenche a área inteira (corta as sobras), um pouco escurecida
        $sc = [math]::Max($w / $src.Width, $h / $src.Height)
        $dw = [int]($src.Width * $sc); $dh = [int]($src.Height * $sc)
        $gr.DrawImage($src, [int](($w - $dw) / 2), [int](($h - $dh) / 3), $dw, $dh)
        $src.Dispose()
        $gr.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, $bg.R, $bg.G, $bg.B))), 0, 0, $w, $h)
    } else {
        # sem arte: a capa bem desfocada (reduz para poucos pixels e amplia de novo)
        $cover = Get-DetailCover $g
        $tiny = New-Object System.Drawing.Bitmap(12, 9)
        $tg = [System.Drawing.Graphics]::FromImage($tiny); $tg.InterpolationMode = 'HighQualityBilinear'
        $tg.DrawImage($cover, 0, -4, 12, 16); $tg.Dispose()
        $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetWrapMode('TileFlipXY')
        $gr.InterpolationMode = 'HighQualityBilinear'
        $gr.DrawImage($tiny, (New-Object System.Drawing.Rectangle(-30, -30, ($w + 60), ($h + 60))), 0, 0, 12, 9, 'Pixel', $ia)
        $tiny.Dispose()
        $gr.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(185, $bg.R, $bg.G, $bg.B))), 0, 0, $w, $h)
    }
    # some na cor do launcher embaixo (os nomes das capas continuam legíveis)
    $gy = [int]($h * 0.45); $gh = $h - $gy + 1
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, ($gy - 2), $w, ($gh + 4))),
        [System.Drawing.Color]::FromArgb(0, $bg.R, $bg.G, $bg.B), $bg, 90)
    $gr.FillRectangle($lg, 0, $gy, $w, $gh)
    # some também nas outras bordas: a arte se funde ao launcher em vez de virar um retângulo
    $clear = [System.Drawing.Color]::FromArgb(0, $bg.R, $bg.G, $bg.B)
    $fades = @(
        @{ x = 0; y = 0; w = $w; h = [math]::Min(110, [int]($h / 3)); a = 270 }
        @{ x = 0; y = 0; w = [math]::Min(70, [int]($w / 6)); h = $h; a = 180 }
        @{ x = $w - [math]::Min(110, [int]($w / 5)); y = 0; w = [math]::Min(110, [int]($w / 5)); h = $h; a = 0 }
    )
    foreach ($f in $fades) {
        $fr = New-Object System.Drawing.Rectangle(($f.x - 1), ($f.y - 1), ($f.w + 2), ($f.h + 2))
        $fb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fr, $clear, $bg, [single]$f.a)
        $gr.FillRectangle($fb, $f.x, $f.y, $f.w, $f.h); $fb.Dispose()
    }
    $gr.Dispose()
    if ($script:LibBackCache.Count -gt 8) { foreach ($v in $script:LibBackCache.Values) { if ($v -ne $script:LibBack) { $v.Dispose() } }; $script:LibBackCache.Clear() }
    $script:LibBackCache[$key] = $bmp
    return $bmp
}

function Update-LibBackdrop {
    $g = Get-Selected
    $w = $lv.ClientSize.Width; $h = $lv.ClientSize.Height
    $new = $null
    if ($g -and $w -gt 20 -and $h -gt 20) { try { $new = New-LibBackdrop $g $w $h } catch { $new = $null } }
    if ($new -eq $script:LibBack) { return }
    $script:LibBack = $new
    $lv.BackgroundImage = $new
    $lv.Invalidate()
}

# troca o fundo um instante depois da escolha (não refaz a imagem a cada item enquanto a lista é montada)
$libBackTimer = New-Object System.Windows.Forms.Timer
$libBackTimer.Interval = 90
$libBackTimer.Add_Tick({ $libBackTimer.Stop(); Update-LibBackdrop })
$lv.Add_SelectedIndexChanged({ if (-not $script:InRefresh) { $libBackTimer.Stop(); $libBackTimer.Start() } })
$lv.Add_Resize({ $libBackTimer.Stop(); $libBackTimer.Start() })

function Invalidate-Card([int]$i) {
    if ($i -lt 0 -or $i -ge $lv.Items.Count) { return }
    $r = $lv.GetItemRect($i)
    $lv.Invalidate((New-Object System.Drawing.Rectangle(($r.X - 6), ($r.Y - 6), ($r.Width + 12), ($CardH + 12))))
}

# animações da interface: um só timer, ligado apenas enquanto há algo em movimento
$script:CardAnim = @{}      # índice do cartão -> posição da animação de 0 (parado) a 1 (em destaque)
$script:TabInk = 1.0
$script:TrBar = 1.0
function Get-Eased([double]$x) { return 1 - [math]::Pow(1 - $x, 3) }
$animTimer = New-Object System.Windows.Forms.Timer
$animTimer.Interval = 16
$animTimer.Add_Tick({
        $busy = $false
        try {
            foreach ($i in @($script:CardAnim.Keys)) {
                if ($i -ge $lv.Items.Count) { $script:CardAnim.Remove($i); continue }
                $t = 0.0; if ($i -eq $script:HotIndex -or $lv.Items[$i].Selected) { $t = 1.0 }
                $v = $script:CardAnim[$i] + ($t - $script:CardAnim[$i]) * 0.3
                if ([math]::Abs($t - $v) -lt 0.03) { $script:CardAnim.Remove($i) } else { $script:CardAnim[$i] = $v; $busy = $true }
                Invalidate-Card $i
            }
            if ($script:TabInk -lt 1) {
                $script:TabInk = [math]::Min(1.0, $script:TabInk + 0.08); $busy = $true
                if ($script:TrophyMode) { $tabTrophy.Invalidate() } elseif ($script:TabButtons[$script:ConsoleFilter]) { $script:TabButtons[$script:ConsoleFilter].Invalidate() }
            }
            if ($script:TrBar -lt 1) {
                $script:TrBar = [math]::Min(1.0, $script:TrBar + 0.045); $busy = $true
                $trGameHead.Invalidate()
            }
        } catch { $busy = $false; Write-AppLog "Animação: $($_.Exception.Message)" }
        if (-not $busy) { $animTimer.Stop() }
    })

$lv.Add_DrawItem({
        $e = $_
        $gr = $e.Graphics
        $gr.SmoothingMode = 'AntiAlias'; $gr.InterpolationMode = 'HighQualityBicubic'; $gr.PixelOffsetMode = 'HighQuality'
        $b = $e.Bounds
        $it = $e.Item
        $isSel = $it.Selected
        $isHot = $e.ItemIndex -eq $script:HotIndex
        # fundo do bloco inteiro (apaga o desenho anterior quando o cartão sobe/desce)
        # fundo do cartão: o pedaço da arte do jogo escolhido que fica ali (ou a cor do launcher)
        $cr = New-Object System.Drawing.Rectangle(($b.X - 6), $b.Y, ($b.Width + 12), $CardH)
        if ($script:LibBack) { $gr.DrawImage($script:LibBack, $cr, $cr, [System.Drawing.GraphicsUnit]::Pixel) }
        else { $gr.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $cr) }
        $cx = $b.X + [int](($b.Width - $GridW) / 2)
        $cy = $b.Y + 8
        $lift = 0.0; if ($isHot -or $isSel) { $lift = 1.0 }
        if ($script:CardAnim.ContainsKey($e.ItemIndex)) { $lift = $script:CardAnim[$e.ItemIndex] }
        $cy -= [int](5 * $lift)   # o cartão "sobe" um pouco
        # sombra: cresce conforme o cartão sobe
        $sh = New-RoundRect ($cx + 2) ($cy + 6 + [int](4 * $lift)) $GridW $GridH 10
        $gr.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb((110 + [int](60 * $lift)), 0, 0, 0))), $sh)
        # brilho atrás do cartão escolhido
        if ($isSel) {
            $glow = New-RoundRect ($cx - 5) ($cy - 5) ($GridW + 10) ($GridH + 10) 14
            $gr.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, $accent.R, $accent.G, $accent.B))), $glow)
        }
        # capa recortada com cantos arredondados
        $path = New-RoundRect $cx $cy $GridW $GridH 10
        $img = $null
        if ($it.ImageKey -and $imgGrid.Images.ContainsKey($it.ImageKey)) { $img = $imgGrid.Images[$it.ImageKey] }
        $gr.SetClip($path)
        if ($img) { $gr.DrawImage($img, $cx, $cy, $GridW, $GridH) }
        else { $gr.FillRectangle((New-Object System.Drawing.SolidBrush($panelBg)), $cx, $cy, $GridW, $GridH) }
        # passar o mouse: clareia um pouco a capa
        if ($lift -gt 0 -and -not $isSel) { $gr.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](28 * $lift), 255, 255, 255))), $cx, $cy, $GridW, $GridH) }
        # favorito: estrela dourada no canto de cima
        if ($it.Tag.favorite) {
            $gr.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(210, 16, 16, 20))), $cx + 6, $cy + 6, 26, 26)
            $sfs = New-Object System.Drawing.StringFormat; $sfs.Alignment = 'Center'; $sfs.LineAlignment = 'Center'
            $gr.DrawString([string][char]$Glyph.star, $fontStar, (New-Object System.Drawing.SolidBrush($FavColor)), (New-Object System.Drawing.RectangleF(($cx + 6), ($cy + 7), 26, 26)), $sfs)
        }
        # novo: adicionado nos últimos 7 dias e ainda não jogado
        if (Test-NewGame $it.Tag) {
            $nx = $cx + $GridW - 52; $ny = $cy + 8
            $gr.FillPath((New-Object System.Drawing.SolidBrush($accent)), (New-RoundRect $nx $ny 44 20 10))
            $sfn = New-Object System.Drawing.StringFormat; $sfn.Alignment = 'Center'; $sfn.LineAlignment = 'Center'
            $gr.DrawString((L ('NOVO')), $fontBadge, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF($nx, ($ny + 1), 44, 20)), $sfn)
        }
        $gr.ResetClip()
        # borda
        if ($isSel) { $pen = New-Object System.Drawing.Pen($accent, 3) }
        else { $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb((55 + [int](95 * $lift)), (55 + [int](95 * $lift)), (66 + [int](104 * $lift))), [single](1 + 0.5 * $lift)) }
        $gr.DrawPath($pen, $path)
        # nome embaixo (até 2 linhas)
        # largura da capa: o Windows corta o que passar da área do item
        $tr = New-Object System.Drawing.Rectangle($cx, ($b.Y + $GridH + 14), $GridW, 36)
        $tf = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, WordBreak, EndEllipsis, NoPrefix'
        if ($isSel) { $tc = $fg; $tfont = $fontCardSel } elseif ($isHot) { $tc = $fg; $tfont = $fontCard } else { $tc = [System.Drawing.Color]::FromArgb(200, 200, 212); $tfont = $fontCard }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($it.Text)), $tfont, $tr, $tc, $tf)
    })

$lv.Add_MouseMove({
        if (-not $lv.OwnerDraw) { return }
        $hit = $lv.HitTest($_.Location).Item
        $i = -1; if ($hit) { $i = $hit.Index }
        if ($i -eq $script:HotIndex) { return }
        $old = $script:HotIndex; $script:HotIndex = $i
        if ($old -ge 0 -and -not $script:CardAnim.ContainsKey($old)) { $script:CardAnim[$old] = 1.0 }
        if ($i -ge 0 -and -not $script:CardAnim.ContainsKey($i)) { $script:CardAnim[$i] = 0.0 }
        $animTimer.Start()
        if ($i -ge 0) { $lv.Cursor = 'Hand' } else { $lv.Cursor = 'Default' }
    })
$lv.Add_MouseLeave({
        $old = $script:HotIndex; $script:HotIndex = -1
        if ($old -ge 0 -and -not $script:CardAnim.ContainsKey($old)) { $script:CardAnim[$old] = 1.0 }
        $animTimer.Start()
        $lv.Cursor = 'Default'
    })

$script:CoverKeys = @{}      # caminho do jogo -> chave da capa
$script:CoverPending = @{}   # chave -> download em andamento (curl em segundo plano)

function Get-CoverImageKey($g) {
    # capa escolhida pela pessoa (arquivo dentro de covers): tem prioridade sobre a automática
    if ($g.cover) {
        $cf = Join-Path $CoverDir $g.cover
        $ck = [IO.Path]::GetFileNameWithoutExtension($g.cover)
        if ($imgCovers.Images.ContainsKey($ck) -and $imgGrid.Images.ContainsKey($ck)) { return $ck }
        if (Test-Path -LiteralPath $cf) {
            try {
                $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($cf)); $img = [System.Drawing.Image]::FromStream($ms)
                $imgCovers.Images.Add($ck, (New-CoverTile $img $g.console))
                $imgGrid.Images.Add($ck, (New-CoverTile $img $g.console $GridW $GridH)); $img.Dispose()
                return $ck
            } catch {}
        }
    }
    $key = $script:CoverKeys[$g.path]
    if (-not $key) { $key = Get-CoverKey $g; $script:CoverKeys[$g.path] = $key }
    if ($imgCovers.Images.ContainsKey($key) -and $imgGrid.Images.ContainsKey($key)) { return $key }
    $file = Join-Path $CoverDir "$key.png"
    if (Test-Path -LiteralPath $file) {
        # capa guardada pequena demais para a grade (versão antiga do launcher): refaz
        try {
            $ms0 = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($file)); $i0 = [System.Drawing.Image]::FromStream($ms0)
            $small = $i0.Width -lt $GridW -and $i0.Height -lt $GridH; $i0.Dispose(); $ms0.Dispose()
            if ($small) { Remove-Item -LiteralPath $file -Force }
        } catch {}
    }
    if (-not (Test-Path -LiteralPath $file)) {
        New-Item -ItemType Directory -Force $CoverDir | Out-Null
        $bytes = Get-LocalCoverBytes $g
        if ($bytes) { [void](Save-CoverFile $bytes $file) }
        elseif ($g.console -eq 'PS2') { Start-CoverDownload $g $key }
    }
    if (Test-Path -LiteralPath $file) {
        try {
            $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($file))   # lê para a memória: não prende o arquivo
            $img = [System.Drawing.Image]::FromStream($ms)
            $imgCovers.Images.Add($key, (New-CoverTile $img $g.console))
            $imgGrid.Images.Add($key, (New-CoverTile $img $g.console $GridW $GridH)); $img.Dispose()
            return $key
        } catch {}
    }
    $ph = 'ph_' + $g.console
    if (-not $imgCovers.Images.ContainsKey($ph)) {
        $imgCovers.Images.Add($ph, (New-CoverPlaceholder $g.console))
        $imgGrid.Images.Add($ph, (New-CoverPlaceholder $g.console $GridW $GridH))
    }
    return $ph
}

function Start-CoverDownload($g, [string]$key) {
    if ($script:CoverPending.ContainsKey($key)) { return }
    $serial = Get-GameSerial $g
    if (-not $serial) { return }
    # já tentou e não achou nos últimos 7 dias: não insiste
    $none = Join-Path $CoverDir "$key.none"
    if ((Test-Path -LiteralPath $none) -and (Get-Item -LiteralPath $none).LastWriteTime -gt (Get-Date).AddDays(-7)) { return }
    $part = Join-Path $CoverDir "$key.part"
    $url = "https://raw.githubusercontent.com/xlenore/ps2-covers/main/covers/default/$serial.jpg"
    try {
        $p = Start-Process curl.exe -ArgumentList "-sL --fail --max-time 30 -o `"$part`" $url" -WindowStyle Hidden -PassThru
        $script:CoverPending[$key] = @{ proc = $p; part = $part; file = (Join-Path $CoverDir "$key.png"); none = $none }
        $coverTimer.Start()
    } catch {}
}

$coverTimer = New-Object System.Windows.Forms.Timer
$coverTimer.Interval = 500
$coverTimer.Add_Tick({
        $done = @($script:CoverPending.Keys | Where-Object { $script:CoverPending[$_].proc.HasExited })
        foreach ($key in $done) {
            $d = $script:CoverPending[$key]; $script:CoverPending.Remove($key)
            $ok = $false
            if ($d.proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $d.part)) { $ok = Save-CoverFile ([IO.File]::ReadAllBytes($d.part)) $d.file }
            Remove-Item -LiteralPath $d.part -ErrorAction SilentlyContinue
            if (-not $ok) { Set-Content -LiteralPath $d.none '' ; continue }
            # troca o quadro provisório pela capa nas linhas desse jogo, sem refazer a lista
            foreach ($it in $lv.Items) {
                if ($script:CoverKeys[$it.Tag.path] -eq $key) { $it.ImageKey = Get-CoverImageKey $it.Tag }
            }
        }
        if ($done.Count) { $script:DetailBackdrops.Clear(); Update-DetailPanel }
        if ($script:CoverPending.Count -eq 0) { $coverTimer.Stop() }
    })

$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'; $bottom.Height = 34; $bottom.BackColor = $panelBg
$lblStatus = New-Label '' 12 8 $dim
$btnView = New-Button 'Ver em lista' 0 3 140 28
$btnView.Dock = 'Right'; $btnView.TextImageRelation = 'ImageBeforeText'; $btnView.Cursor = 'Hand'
$btnView.FlatAppearance.BorderSize = 0; $btnView.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnView.Add_Click({
        if ($script:ViewMode -eq 'lista') { $m = 'grade' } else { $m = 'lista' }
        Set-LibraryView $m
        $script:Cfg.viewMode = $m; Save-Config
    })
$btnHelp = New-Button '  Primeiros passos' 0 3 160 28
$btnHelp.Dock = 'Right'; $btnHelp.TextImageRelation = 'ImageBeforeText'; $btnHelp.Cursor = 'Hand'
$btnHelp.Image = New-GlyphImage 0xE897 14 $fg
$btnHelp.FlatAppearance.BorderSize = 0; $btnHelp.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnHelp.Add_Click({ Show-SetupAssistant; Refresh-List })
$btnSize = New-Button '  Capas: Médio' 0 3 130 28
$btnSize.Dock = 'Right'; $btnSize.TextImageRelation = 'ImageBeforeText'; $btnSize.Cursor = 'Hand'
$btnSize.Image = New-GlyphImage 0xE740 14 $fg
$btnSize.FlatAppearance.BorderSize = 0; $btnSize.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnSize.Add_Click({ Show-SizeMenu })
$btnAbout = New-Button '  Sobre' 0 3 92 28
$btnAbout.Dock = 'Right'; $btnAbout.TextImageRelation = 'ImageBeforeText'; $btnAbout.Cursor = 'Hand'
$btnAbout.Image = New-GlyphImage 0xE946 14 $fg
$btnAbout.FlatAppearance.BorderSize = 0; $btnAbout.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnAbout.Add_Click({ Show-AboutDialog })
$btnSaves = New-Button '  Saves' 0 3 92 28
$btnSaves.Dock = 'Right'; $btnSaves.TextImageRelation = 'ImageBeforeText'; $btnSaves.Cursor = 'Hand'
$btnSaves.Image = New-GlyphImage 0xE74E 14 $fg
$btnSaves.FlatAppearance.BorderSize = 0; $btnSaves.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnSaves.Add_Click({ Show-SavesDialog })
$btnTv = New-Button '  Modo TV' 0 3 104 28
$btnTv.Dock = 'Right'; $btnTv.TextImageRelation = 'ImageBeforeText'; $btnTv.Cursor = 'Hand'
$btnTv.Image = New-GlyphImage 0xE7F4 14 $fg
$btnTv.FlatAppearance.BorderSize = 0; $btnTv.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
$btnTv.Add_Click({ Show-TvMode })
# barra de baixo só com o aviso, o tamanho das capas e grade/lista
# (Modo TV fica em cima; Saves, Primeiros passos e Sobre no botão ⋯ de cima)
$lblStatus.AutoSize = $false; $lblStatus.Dock = 'Fill'; $lblStatus.AutoEllipsis = $true
$lblStatus.TextAlign = 'MiddleLeft'; $lblStatus.Padding = New-Object System.Windows.Forms.Padding(12, 0, 8, 0)
$bottom.Add_Paint({ $_.Graphics.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 50, 60))), 0, 0, $this.Width, 0) })
$bottom.Controls.Add($lblStatus)
$bottom.Controls.Add($btnSize)
$bottom.Controls.Add($btnView)

# margem em volta da biblioteca (sem ela as capas ficam coladas na barra de cima)
$libPanel = New-Object System.Windows.Forms.Panel
$libPanel.Dock = 'Fill'; $libPanel.BackColor = $bg; $libPanel.Padding = New-Object System.Windows.Forms.Padding(14, 12, 6, 0)
$lv.Dock = 'Fill'
$libPanel.Controls.Add($lv)
$form.Controls.Add($libPanel)

# ---- aviso no meio da tela quando não há jogos para mostrar (biblioteca vazia, aba vazia ou busca sem resultado)
$emptyPanel = New-Object System.Windows.Forms.Panel
$emptyPanel.Size = New-Object System.Drawing.Size(680, 270); $emptyPanel.BackColor = $bg; $emptyPanel.Visible = $false
$emptyIcon = New-Object System.Windows.Forms.PictureBox
$emptyIcon.SetBounds(0, 0, 680, 70); $emptyIcon.SizeMode = 'CenterImage'
$emptyTitle = New-Object System.Windows.Forms.Label
$emptyTitle.SetBounds(0, 78, 680, 32); $emptyTitle.TextAlign = 'MiddleCenter'; $emptyTitle.ForeColor = $fg
$emptyTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$emptyText = New-Object System.Windows.Forms.Label
$emptyText.SetBounds(40, 114, 600, 70); $emptyText.TextAlign = 'TopCenter'; $emptyText.ForeColor = $dim
$emptyText.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
$emptyBtns = New-Object System.Windows.Forms.FlowLayoutPanel
$emptyBtns.SetBounds(0, 196, 680, 50); $emptyBtns.WrapContents = $false; $emptyBtns.BackColor = $bg
$btnEmptyAdd = New-TopButton 'Adicionar jogo' 'add' $true
$btnEmptyDir = New-TopButton 'Adicionar pasta' 'folder'
$btnEmptyClear = New-TopButton 'Limpar busca' 'search'
$btnEmptyAll = New-TopButton 'Ver todos os jogos' 'grid'
$btnEmptyAdd.Add_Click({ Invoke-AddFiles })
$btnEmptyDir.Add_Click({ Invoke-AddFolder })
$btnEmptyClear.Add_Click({ $txtSearch.Text = '' })
$btnEmptyAll.Add_Click({ Set-ConsoleFilter 'Todos' })
$emptyBtns.Controls.AddRange(@($btnEmptyAdd, $btnEmptyDir, $btnEmptyClear, $btnEmptyAll))
$emptyPanel.Controls.AddRange(@($emptyIcon, $emptyTitle, $emptyText, $emptyBtns))
$libPanel.Controls.Add($emptyPanel)
$emptyPanel.BringToFront()

$script:CenterEmpty = {
    $emptyPanel.Left = [int](($libPanel.ClientSize.Width - $emptyPanel.Width) / 2)
    $emptyPanel.Top = [int](($libPanel.ClientSize.Height - $emptyPanel.Height) / 2.4)
    # centraliza a fileira de botões. A lista de botões mostrados é guardada à parte:
    # Control.Visible responde falso enquanto o aviso ainda está escondido, e a conta dava zero.
    $w = 0; foreach ($c in $script:EmptyBtnsShown) { $w += $c.Width + $c.Margin.Right }
    $w -= 8   # sem margem depois do último
    $emptyBtns.Padding = New-Object System.Windows.Forms.Padding([math]::Max(0, [int](($emptyBtns.Width - $w) / 2)), 0, 0, 0)
}
$script:EmptyBtnsShown = @()
$libPanel.Add_Resize({ & $script:CenterEmpty })

$ConsoleHints = @{
    PS2 = 'Jogos de PS2: arquivos .iso, .chd, .cso, .bin...'
    PS3 = 'Jogos de PS3: .iso, .pkg ou a pasta do jogo (com PS3_GAME ou EBOOT.BIN).'
    PS4 = 'Jogos de PS4: a pasta do jogo (com eboot.bin e sce_sys) ou um arquivo .pkg.'
}

function Update-EmptyState {
    # na lista sem jogos sobraria só o cabeçalho branco do Windows em cima do aviso
    $lv.Visible = $lv.Items.Count -gt 0 -or $lv.View -ne 'Details'
    if ($lv.Items.Count -gt 0) { $emptyPanel.Visible = $false; return }
    $search = $txtSearch.Text.Trim()
    $cons = $script:ConsoleFilter
    $show = @($btnEmptyAdd, $btnEmptyDir)
    if ($search) {
        $emptyIcon.Image = New-GlyphImage $Glyph.search 44 $dim
        $where = if ($cons -ne 'Todos') { " nos jogos de $cons" } else { '' }
        $emptyTitle.Text = "Nenhum jogo encontrado para ""$search"""
        $emptyText.Text = "Não há jogo com esse nome$where. Confira se o nome está certo ou limpe a busca."
        $show = @($btnEmptyClear)
    } elseif (@($script:Cfg.games).Count -eq 0) {
        $emptyIcon.Image = New-GlyphImage $Glyph.emus 48 $dim
        $emptyTitle.Text = 'Sua biblioteca está vazia'
        $emptyText.Text = "Arraste seus jogos (ISO, PKG ou a pasta do jogo) para esta janela,`nou use os botões abaixo. PS2, PS3 e PS4 são reconhecidos sozinhos."
    } elseif ($cons -eq 'Favoritos') {
        $emptyIcon.Image = New-GlyphImage $Glyph.star 48 $FavColor
        $emptyTitle.Text = 'Nenhum favorito ainda'
        $emptyText.Text = "Clique na estrela em cima da capa grande (à direita), ou com o botão direito`nnuma capa > Adicionar aos favoritos. Atalho: Ctrl+D."
        $show = @($btnEmptyAll)
    } else {
        $emptyIcon.Image = New-GlyphImage $Glyph.emus 48 $dim
        $emptyTitle.Text = "Nenhum jogo de $cons ainda"
        $emptyText.Text = "$($ConsoleHints[$cons])`nArraste para esta janela ou use os botões abaixo."
        $show = @($btnEmptyAdd, $btnEmptyDir, $btnEmptyAll)
    }
    foreach ($b in @($btnEmptyAdd, $btnEmptyDir, $btnEmptyClear, $btnEmptyAll)) { $b.Visible = $show -contains $b }
    $script:EmptyBtnsShown = $show
    & $script:CenterEmpty
    $emptyPanel.Visible = $true
    $emptyBtns.PerformLayout()
}

# soltar arquivos em cima do aviso também adiciona
foreach ($ctl in @($libPanel, $emptyPanel, $emptyIcon, $emptyTitle, $emptyText)) {
    $ctl.AllowDrop = $true
    $ctl.Add_DragEnter({ if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
    $ctl.Add_DragDrop({ Add-Games ([string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) })
}

# ---- abas: Todos / Favoritos / PS2 / PS3 / PS4 (com a quantidade de jogos)
$TabNames = @('Todos', 'Favoritos', 'PS2', 'PS3', 'PS4')
$FavColor = [System.Drawing.Color]::FromArgb(255, 200, 70)
$script:ConsoleFilter = 'Todos'
$script:TabButtons = [ordered]@{}

function Test-InTab($g, [string]$tab) {
    if ($tab -eq 'Todos') { return $true }
    if ($tab -eq 'Favoritos') { return [bool]$g.favorite }
    return (Get-ConsoleKind $g) -eq $tab
}

$tabsBar = New-Object System.Windows.Forms.FlowLayoutPanel
$tabsBar.Dock = 'Top'; $tabsBar.Height = 44; $tabsBar.BackColor = $bg; $tabsBar.WrapContents = $false
$tabsBar.Padding = New-Object System.Windows.Forms.Padding(14, 6, 0, 0)
foreach ($name in $TabNames) {
    $tb = New-Object System.Windows.Forms.Button
    $tb.Text = $name; $tb.Tag = $name; $tb.Height = 36; $tb.Width = 96
    $tb.FlatStyle = 'Flat'; $tb.FlatAppearance.BorderSize = 0; $tb.Cursor = 'Hand'
    $tb.BackColor = $bg; $tb.ForeColor = $dim; $tb.Font = $fontBold
    $tb.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(36, 36, 44)
    $tb.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(36, 36, 44)
    $tb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    # aba escolhida: texto claro e linha embaixo na cor do console
    $tb.Add_Paint({
            if ($this.Tag -ne $script:ConsoleFilter -or $script:TrophyMode) { return }
            $c = $accent
            if ($consoleColors.ContainsKey($this.Tag)) { $c = $consoleColors[$this.Tag] }
            if ($this.Tag -eq 'Favoritos') { $c = $FavColor }
            # a linha abre do centro para as pontas ao trocar de aba
            $iw = [int](($this.Width - 20) * (Get-Eased $script:TabInk))
            $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($c)), [int](($this.Width - $iw) / 2), $this.Height - 3, $iw, 3)
        })
    $tb.Add_Click({ Set-ConsoleFilter $this.Tag })
    if ($name -eq 'Favoritos') {
        $tb.Image = New-GlyphImage 0xE735 13 $FavColor
        $tb.TextImageRelation = 'ImageBeforeText'
    }
    $script:TabButtons[$name] = $tb
    $tabsBar.Controls.Add($tb)
}

# aba Conquistas: troca a biblioteca pela tela de troféus
$script:TrophyMode = $false
$tabTrophy = New-Object System.Windows.Forms.Button
$tabTrophy.Text = L 'Conquistas'; $tabTrophy.Height = 36
$tabTrophy.FlatStyle = 'Flat'; $tabTrophy.FlatAppearance.BorderSize = 0; $tabTrophy.Cursor = 'Hand'
$tabTrophy.BackColor = $bg; $tabTrophy.ForeColor = $dim; $tabTrophy.Font = $fontBold
$tabTrophy.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(36, 36, 44)
$tabTrophy.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(36, 36, 44)
$tabTrophy.Image = New-CupImage 13 $TrophyColors.G; $tabTrophy.TextImageRelation = 'ImageBeforeText'
$tabTrophy.Width = [System.Windows.Forms.TextRenderer]::MeasureText($tabTrophy.Text, $tabTrophy.Font).Width + 44
$tabTrophy.Margin = New-Object System.Windows.Forms.Padding(14, 0, 6, 0)
$tabTrophy.Add_Paint({
        if (-not $script:TrophyMode) { return }
        $iw = [int](($this.Width - 20) * (Get-Eased $script:TabInk))
        $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($TrophyColors.G)), [int](($this.Width - $iw) / 2), $this.Height - 3, $iw, 3)
    })
$tabTrophy.Add_Click({ Show-TrophyView })
$tabsBar.Controls.Add($tabTrophy)

# ---- ordenar a biblioteca (fica à direita das abas)
$SortModes = [ordered]@{ nome = 'Nome'; recentes = 'Jogados recentemente'; tempo = 'Mais tempo jogado'; adicionados = 'Adicionados por último' }
$script:SortMode = 'nome'
$btnSort = New-Object System.Windows.Forms.Button
$btnSort.Height = 36; $btnSort.FlatStyle = 'Flat'; $btnSort.FlatAppearance.BorderSize = 0; $btnSort.Cursor = 'Hand'
$btnSort.BackColor = $bg; $btnSort.ForeColor = $dim; $btnSort.Font = $font
$btnSort.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(36, 36, 44)
$btnSort.Image = New-GlyphImage 0xE8CB 14 $dim; $btnSort.TextImageRelation = 'ImageBeforeText'
$btnSort.Margin = New-Object System.Windows.Forms.Padding(24, 0, 0, 0)
$tabsBar.Controls.Add($btnSort)
$btnSort.Add_Click({ $sortMenu.Show($btnSort, (New-Object System.Drawing.Point(0, $btnSort.Height))) })

function Set-SortMode([string]$mode) {
    if (-not $SortModes.Contains($mode)) { $mode = 'nome' }
    $script:SortMode = $mode
    $btnSort.Text = '  ' + (L ("Ordenar: $($SortModes[$mode])  " + [char]0x25BE))
    $btnSort.Width = [System.Windows.Forms.TextRenderer]::MeasureText($btnSort.Text, $btnSort.Font).Width + 34
}

function Get-SortedGames {
    $all = @($script:Cfg.games)
    switch ($script:SortMode) {
        'recentes' { return $all | Sort-Object @{ Expression = { [string]$_.lastPlayed }; Descending = $true }, name }
        'tempo' { return $all | Sort-Object @{ Expression = { [int]$_.playSeconds }; Descending = $true }, name }
        'adicionados' { return $all | Sort-Object @{ Expression = { [string]$_.added }; Descending = $true }, name }
        default { return $all | Sort-Object name }
    }
}

function Set-Favorite($g, [bool]$on) {
    if ($on) { $g | Add-Member -NotePropertyName favorite -NotePropertyValue $true -Force }
    else { $g.PSObject.Properties.Remove('favorite') }
    Save-Config; Refresh-List; [void](Select-Game $g)
    if ($on) { Show-Toast "$($g.name) nos favoritos" 'ok' } else { Show-Toast "$($g.name) saiu dos favoritos" 'info' }
}

function Set-ConsoleFilter([string]$name) {
    Invoke-UiFrozen {
        Hide-TrophyView
        $script:ConsoleFilter = $name
        $script:Cfg.consoleFilter = $name; Save-Config
        Refresh-List
    }
}

function Update-ConsoleTabs {
    $counts = @{ Todos = 0; Favoritos = 0; PS2 = 0; PS3 = 0; PS4 = 0 }
    foreach ($g in $script:Cfg.games) {
        $counts.Todos++; $k = Get-ConsoleKind $g; if ($counts.ContainsKey($k)) { $counts[$k]++ }
        if ($g.favorite) { $counts.Favoritos++ }
    }
    foreach ($name in $script:TabButtons.Keys) {
        $tb = $script:TabButtons[$name]
        $tb.Text = "$name  $($counts[$name])"
        $tb.Width = [System.Windows.Forms.TextRenderer]::MeasureText($tb.Text, $tb.Font).Width + 34
        if ($name -eq $script:ConsoleFilter -and -not $script:TrophyMode) { $tb.ForeColor = $fg } else { $tb.ForeColor = $dim }
        $tb.Invalidate()
    }
    if ($script:TrophyMode) { $tabTrophy.ForeColor = $fg } else { $tabTrophy.ForeColor = $dim }
    $tabTrophy.Invalidate()
    $active = "$($script:TrophyMode)|$($script:ConsoleFilter)"
    if ($script:TabActive -and $active -ne $script:TabActive) { $script:TabInk = 0.0; $animTimer.Start() }
    $script:TabActive = $active
}

# ---- painel do jogo (à direita): capa grande, console, tempo jogado, JOGAR e atalhos
$DetailW = 200; $DetailH = 266
$script:DetailCovers = @{}   # chave da capa -> imagem grande já montada
$detail = New-Object System.Windows.Forms.Panel
$detail.Dock = 'Right'; $detail.Width = 300; $detail.BackColor = $panelBg; $detail.AutoScroll = $true
$detail.Add_Paint({ $_.Graphics.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 50, 60))), 0, 0, 0, $this.Height) })

$dtCover = New-Object System.Windows.Forms.PictureBox
$dtCover.SetBounds(50, 20, $DetailW, $DetailH)
$dtName = New-Object System.Windows.Forms.Label
$dtName.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$dtName.ForeColor = $fg; $dtName.TextAlign = 'TopCenter'; $dtName.AutoEllipsis = $true
$dtChip = New-Object System.Windows.Forms.Label
$dtChip.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$dtChip.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28); $dtChip.TextAlign = 'MiddleCenter'
$dtPreset = New-Object System.Windows.Forms.Label
$dtPreset.Font = New-Object System.Drawing.Font('Segoe UI', 9); $dtPreset.ForeColor = $dim; $dtPreset.TextAlign = 'MiddleLeft'
$fontCap = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$fontVal = New-Object System.Drawing.Font('Segoe UI', 10.5)
$dtTimeCap = New-Object System.Windows.Forms.Label; $dtTimeCap.Text = 'TEMPO JOGADO'
$dtLastCap = New-Object System.Windows.Forms.Label; $dtLastCap.Text = 'ÚLTIMA VEZ'
$dtTime = New-Object System.Windows.Forms.Label
$dtLast = New-Object System.Windows.Forms.Label
foreach ($l in $dtTimeCap, $dtLastCap) { $l.Font = $fontCap; $l.ForeColor = $dim }
foreach ($l in $dtTime, $dtLast) { $l.Font = $fontVal; $l.ForeColor = $fg; $l.AutoEllipsis = $true }

$dtPlay = New-Object System.Windows.Forms.Button
$dtPlay.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$dtPlay.Image = New-GlyphImage $Glyph.play 18 $fg
$dtPlay.TextImageRelation = 'ImageBeforeText'; $dtPlay.ImageAlign = 'MiddleCenter'; $dtPlay.TextAlign = 'MiddleCenter'
$dtPlay.FlatStyle = 'Flat'; $dtPlay.FlatAppearance.BorderSize = 0; $dtPlay.Cursor = 'Hand'
$dtPlay.BackColor = $accent; $dtPlay.ForeColor = $fg
$dtPlay.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(95, 135, 245)
$dtPlay.Add_Click({ Play-Selected })

function New-DetailButton([string]$text, [string]$iconName) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Size = New-Object System.Drawing.Size(84, 54)
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $b.Image = New-GlyphImage $Glyph[$iconName] 16 $fg
    $b.TextImageRelation = 'ImageAboveText'; $b.ImageAlign = 'MiddleCenter'; $b.TextAlign = 'MiddleCenter'
    $b.FlatStyle = 'Flat'; $b.ForeColor = $fg; $b.Cursor = 'Hand'
    $b.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 52)
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(62, 62, 74)
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
    return $b
}
$dtBtnCfg = New-DetailButton 'Configurar' 'settings'
$dtBtnDir = New-DetailButton 'Abrir pasta' 'folder'
$dtBtnDel = New-DetailButton 'Remover' 'remove'
$dtBtnCfg.Add_Click({ Invoke-GameSettings })
$dtBtnDel.Add_Click({ Invoke-RemoveGame })
$dtBtnDir.Add_Click({
        $g = Get-Selected
        if (-not $g) { return }
        if (Test-Path -LiteralPath $g.path -PathType Container) { Start-Process explorer.exe "`"$($g.path)`"" }
        elseif (Test-Path -LiteralPath $g.path) { Start-Process explorer.exe "/select,`"$($g.path)`"" }
        else { Set-Status "Arquivo não encontrado: $($g.path)" }
    })
$dtFile = New-Object System.Windows.Forms.Label
$dtFile.Font = New-Object System.Drawing.Font('Segoe UI', 8.5); $dtFile.ForeColor = $dim; $dtFile.AutoEllipsis = $true
$dtTip = New-Object System.Windows.Forms.ToolTip

# sem jogo escolhido
$dtEmptyIcon = New-Object System.Windows.Forms.PictureBox
$dtEmptyIcon.SetBounds(0, 170, 300, 60); $dtEmptyIcon.SizeMode = 'CenterImage'
$dtEmptyIcon.Image = New-GlyphImage $Glyph.emus 40 $dim
$dtEmptyText = New-Object System.Windows.Forms.Label
$dtEmptyText.SetBounds(30, 236, 240, 60); $dtEmptyText.TextAlign = 'TopCenter'; $dtEmptyText.ForeColor = $dim
$dtEmptyText.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$dtEmptyText.Text = 'Escolha um jogo para ver os detalhes aqui.'

# estrela de favorito no canto da capa grande
# (desenhada à mão: um Button com Region redonda não completa o clique)
$dtFav = New-Object System.Windows.Forms.PictureBox
$dtFav.Size = New-Object System.Drawing.Size(34, 34); $dtFav.Cursor = 'Hand'; $dtFav.BackColor = [System.Drawing.Color]::Transparent
$dtFav.Tag = @{ on = $false; hot = $false }
$dtFav.Add_Paint({
        $fg2 = $_.Graphics; $fg2.SmoothingMode = 'AntiAlias'; $fg2.TextRenderingHint = 'AntiAliasGridFit'
        $st = $this.Tag
        $c = if ($st.hot) { [System.Drawing.Color]::FromArgb(230, 50, 50, 62) } else { [System.Drawing.Color]::FromArgb(210, 20, 20, 26) }
        $fg2.FillEllipse((New-Object System.Drawing.SolidBrush($c)), 0, 0, 33, 33)
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        if ($st.on) { $code = $Glyph.star; $col = $FavColor } else { $code = $Glyph.trophy; $col = $fg }
        $fg2.DrawString([string][char]$code, (New-Object System.Drawing.Font($IconFont, 12)), (New-Object System.Drawing.SolidBrush($col)), (New-Object System.Drawing.RectangleF(0, 1, 34, 34)), $sf)
    })
$dtFav.Add_MouseEnter({ $this.Tag.hot = $true; $this.Invalidate() })
$dtFav.Add_MouseLeave({ $this.Tag.hot = $false; $this.Invalidate() })
# reage ao soltar o botão: por cima da capa o Windows não entrega o Click
$dtFav.Add_MouseUp({
        if ($_.Button -ne 'Left' -or -not $this.ClientRectangle.Contains($_.Location)) { return }
        $g = Get-Selected; if ($g) { Set-Favorite $g (-not $g.favorite) }
    })
$dtTip.SetToolTip($dtFav, (L 'Favorito (Ctrl+D)'))

$script:DetailBody = @($dtFav, $dtCover,$dtName, $dtChip, $dtPreset, $dtTimeCap, $dtLastCap, $dtTime, $dtLast, $dtPlay, $dtBtnCfg, $dtBtnDir, $dtBtnDel, $dtFile)
$detail.BackgroundImageLayout = 'None'
# textos por cima do fundo desfocado
foreach ($l in $dtCover, $dtName, $dtPreset, $dtTimeCap, $dtLastCap, $dtTime, $dtLast, $dtFile, $dtEmptyText, $dtEmptyIcon) { $l.BackColor = [System.Drawing.Color]::Transparent }
$detail.Controls.AddRange($script:DetailBody)
$detail.Controls.AddRange(@($dtEmptyIcon, $dtEmptyText))

function Add-PlayTime($g, [int]$secs) {
    $total = [int]$g.playSeconds + [math]::Max(0, $secs)
    $g | Add-Member -NotePropertyName playSeconds -NotePropertyValue $total -Force
    $g | Add-Member -NotePropertyName lastPlayed -NotePropertyValue ((Get-Date).ToString('yyyy-MM-dd HH:mm')) -Force
    Save-Config
}

function Format-PlayTime([int]$secs) {
    if ($secs -lt 60) { if ($secs -gt 0) { return 'Menos de 1 min' } else { return 'Ainda não jogado' } }
    $m = [int][math]::Floor($secs / 60)
    if ($m -lt 60) { return "$m min" }
    return "$([int][math]::Floor($m / 60)) h $($m % 60) min"
}

function Format-LastPlayed([string]$when) {
    if (-not $when) { return '-' }
    try { $d = [datetime]::ParseExact($when, 'yyyy-MM-dd HH:mm', $null) } catch { return '-' }
    $days = ((Get-Date).Date - $d.Date).Days
    if ($days -eq 0) { return "Hoje, $($d.ToString('HH:mm'))" }
    if ($days -eq 1) { return "Ontem, $($d.ToString('HH:mm'))" }
    return $d.ToString('dd/MM/yyyy')
}

function Get-DetailCover($g) {
    $key = Get-CoverImageKey $g
    if ($script:DetailCovers.ContainsKey($key)) { return $script:DetailCovers[$key] }
    $img = $null
    $file = Join-Path $CoverDir "$key.png"
    if (-not $key.StartsWith('ph_') -and (Test-Path -LiteralPath $file)) {
        try { $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($file)); $img = [System.Drawing.Image]::FromStream($ms) } catch {}
    }
    $tile = New-CoverTile $img $g.console $DetailW $DetailH
    if ($img) { $img.Dispose() }
    $script:DetailCovers[$key] = $tile
    return $tile
}

$script:DetailBackdrops = @{}
function Get-DetailBackdrop($g) {
    # fundo do painel: a própria capa bem desfocada e escura, sumindo na cor do painel
    $key = Get-CoverImageKey $g
    if ($script:DetailBackdrops.ContainsKey($key)) { return $script:DetailBackdrops[$key] }
    $cover = Get-DetailCover $g
    $bw = 300; $bh = 560
    # desfoque barato: reduz para poucos pixels e amplia de novo com suavização
    $tiny = New-Object System.Drawing.Bitmap(12, 16)
    $tg = [System.Drawing.Graphics]::FromImage($tiny); $tg.InterpolationMode = 'HighQualityBilinear'
    $tg.DrawImage($cover, 0, 0, 12, 16); $tg.Dispose()
    $bmp = New-Object System.Drawing.Bitmap($bw, $bh)
    $bgr = [System.Drawing.Graphics]::FromImage($bmp)
    $bgr.Clear($panelBg)
    $bgr.InterpolationMode = 'HighQualityBilinear'
    $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetWrapMode('TileFlipXY')
    $bgr.DrawImage($tiny, (New-Object System.Drawing.Rectangle(-20, -20, ($bw + 40), 440)), 0, 0, 12, 16, 'Pixel', $ia)
    $bgr.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(85, 14, 14, 18))), 0, 0, $bw, $bh)
    # some na cor do painel de cima para baixo
    $fadeTop = 210
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, $fadeTop, $bw, 260)),
        [System.Drawing.Color]::FromArgb(0, $panelBg.R, $panelBg.G, $panelBg.B), $panelBg, 90)
    $bgr.FillRectangle($lg, 0, $fadeTop, $bw, 260)
    $bgr.FillRectangle((New-Object System.Drawing.SolidBrush($panelBg)), 0, $fadeTop + 259, $bw, $bh)
    $bgr.Dispose(); $tiny.Dispose()
    $script:DetailBackdrops[$key] = $bmp
    return $bmp
}

function Update-DetailPanel {
    if ($script:InRefresh) { return }
    # aba ou busca sem jogos: o aviso do meio já explica, o painel sai da frente
    $detail.Visible = $lv.Items.Count -gt 0 -and -not $script:TrophyMode
    $g = Get-Selected
    $has = [bool]$g
    foreach ($c in $script:DetailBody) { $c.Visible = $has }
    $dtEmptyIcon.Visible = -not $has; $dtEmptyText.Visible = -not $has
    if (-not $has) { $detail.BackgroundImage = $null; return }
    $cw = 260   # largura útil do painel
    $dtCover.Image = Get-DetailCover $g
    $detail.BackgroundImage = Get-DetailBackdrop $g
    $dtName.Text = $g.name
    $nh = [System.Windows.Forms.TextRenderer]::MeasureText($g.name, $dtName.Font, (New-Object System.Drawing.Size($cw, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height
    # capa encolhe um pouco em janela baixa ou nome longo, para tudo caber sem rolagem
    $rest = 14 + [math]::Min($nh, 78) + 8 + 38 + 52 + 56 + 64 + 18 + 28
    $ch = [math]::Max(170, [math]::Min($DetailH, $detail.ClientSize.Height - $rest))
    $cwid = [int]($ch * $DetailW / $DetailH)
    $dtCover.SizeMode = 'Zoom'
    $dtCover.SetBounds([int]((300 - $cwid) / 2), 20, $cwid, $ch)
    $dtFav.Location = New-Object System.Drawing.Point(($dtCover.Right - 42), 28)
    $dtFav.Tag.on = [bool]$g.favorite; $dtFav.Invalidate()
    $dtFav.BringToFront()
    $y = $dtCover.Bottom + 14
    $dtName.SetBounds(20, $y, $cw, [math]::Min($nh, 78)); $y = $dtName.Bottom + 8

    # etiqueta do console na cor dele + predefinição, centralizadas
    $c = $accent
    if ($consoleColors.ContainsKey($g.console)) { $c = $consoleColors[$g.console] }
    $dtChip.Text = $g.console -replace ' \(PKG\)', ' PKG'; $dtChip.ForeColor = $c
    $dtPreset.Text = (Get-GameSettings $g).preset
    # PS4: versão do jogo junto (os patches dependem dela)
    if ((Get-ConsoleKind $g) -eq 'PS4' -and (Test-Path -LiteralPath $g.path)) {
        $av = Get-Ps4AppVersion $g.path
        if ($av) { $dtPreset.Text += "  ·  v$av" }
    }
    $chipW = [System.Windows.Forms.TextRenderer]::MeasureText($dtChip.Text, $dtChip.Font).Width + 16
    $preW = [System.Windows.Forms.TextRenderer]::MeasureText($dtPreset.Text, $dtPreset.Font).Width + 4
    $x = 20 + [int](($cw - ($chipW + 8 + $preW)) / 2)
    $dtChip.SetBounds($x, $y, $chipW, 24)
    $dtPreset.SetBounds($x + $chipW + 8, $y, $preW, 24)
    $y += 38

    $dtTimeCap.SetBounds(20, $y, 125, 16); $dtLastCap.SetBounds(155, $y, 125, 16)
    $dtTime.SetBounds(20, $y + 16, 130, 22); $dtLast.SetBounds(155, $y + 16, 125, 22)
    $dtTime.Text = Format-PlayTime ([int]$g.playSeconds)
    $dtLast.Text = Format-LastPlayed $g.lastPlayed
    $y += 52

    if ($script:RunDir -and $script:RunGame -and $script:RunGame.path -eq $g.path) {
        $dtPlay.Text = '  JOGANDO AGORA'; $dtPlay.Enabled = $false; $dtPlay.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 52)
    } else {
        $dtPlay.Text = '  JOGAR'; $dtPlay.Enabled = $true; $dtPlay.BackColor = $accent
    }
    $dtPlay.SetBounds(20, $y, $cw, 48); $y += 56
    $dtBtnCfg.Location = New-Object System.Drawing.Point(20, $y)
    $dtBtnDir.Location = New-Object System.Drawing.Point(108, $y)
    $dtBtnDel.Location = New-Object System.Drawing.Point(196, $y)
    $y += 64
    $dtFile.Text = $g.path; $dtFile.SetBounds(20, $y, $cw, 18)
    $dtTip.SetToolTip($dtFile, $g.path)
}

$detail.Add_Resize({ if ($script:DetailReady) { Update-DetailPanel } })
$lv.Add_SelectedIndexChanged({
        # redesenha a grade inteira: o nome do escolhido (negrito) ocupa mais área e deixaria restos ao trocar
        if ($lv.OwnerDraw) { $lv.Invalidate() }
        Update-DetailPanel
    })

function Select-Game($g) {
    # escolhe o jogo na grade/lista e mostra ele na tela
    foreach ($it in $lv.Items) {
        if ($it.Tag.path -eq $g.path) {
            $it.Selected = $true; $it.Focused = $true; $it.EnsureVisible()
            return $true
        }
    }
    return $false
}

# ---- avisos no canto (toasts): aparecem deslizando e somem sozinhos, sem caixa de OK
$ToastColors = @{
    info = $accent
    ok   = [System.Drawing.Color]::FromArgb(110, 220, 140)
    warn = [System.Drawing.Color]::FromArgb(255, 170, 90)
}
$ToastGlyphs = @{ info = 0xE946; ok = 0xE73E; warn = 0xE7BA }
$toast = New-Object System.Windows.Forms.Panel
$toast.Visible = $false; $toast.BackColor = [System.Drawing.Color]::FromArgb(48, 48, 58); $toast.Height = 48
$toastIcon = New-Object System.Windows.Forms.PictureBox
$toastIcon.SetBounds(12, 0, 24, 48); $toastIcon.SizeMode = 'CenterImage'
$toastText = New-Object System.Windows.Forms.Label
$toastText.Font = New-Object System.Drawing.Font('Segoe UI', 10); $toastText.ForeColor = $fg
$toastText.TextAlign = 'MiddleLeft'; $toastText.AutoEllipsis = $true
$toastAction = New-Object System.Windows.Forms.Button
$toastAction.FlatStyle = 'Flat'; $toastAction.FlatAppearance.BorderSize = 0; $toastAction.Cursor = 'Hand'
$toastAction.Font = $fontBold; $toastAction.ForeColor = [System.Drawing.Color]::FromArgb(130, 165, 255)
$toastAction.BackColor = $toast.BackColor
$toastAction.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(62, 62, 76)
$toast.Controls.AddRange(@($toastIcon, $toastText, $toastAction))
$toast.Add_Paint({ $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush($script:ToastColor)), 0, 0, 4, $this.Height) })
$script:ToastColor = $accent
$toastAction.Add_Click({
        $toast.Visible = $false; $toastTimer.Stop()
        if ($script:ToastActionBlock) { & $script:ToastActionBlock }
    })
$toastText.Add_Click({ $toast.Visible = $false; $toastTimer.Stop() })
$toastTimer = New-Object System.Windows.Forms.Timer
$toastTimer.Interval = 15
$toastTimer.Add_Tick({
        # desliza até o lugar, espera e some
        $script:ToastTicks++
        if ($toast.Top -gt $script:ToastY) { $toast.Top = [math]::Max($script:ToastY, $toast.Top - 4) }
        if ($script:ToastTicks * 15 -ge $script:ToastLife) { $toast.Visible = $false; $toastTimer.Stop() }
    })

function Show-Toast([string]$text, [string]$kind = 'info', [string]$actionText = '', [scriptblock]$action = $null) {
    if (-not $ToastColors.ContainsKey($kind)) { $kind = 'info' }
    $script:ToastColor = $ToastColors[$kind]
    $toastIcon.Image = New-GlyphImage $ToastGlyphs[$kind] 16 $ToastColors[$kind]
    $toastText.Text = $text
    $tw = [System.Windows.Forms.TextRenderer]::MeasureText($text, $toastText.Font).Width + 8
    $aw = 0
    $toastAction.Visible = [bool]$actionText
    if ($actionText) {
        $toastAction.Text = $actionText
        $aw = [System.Windows.Forms.TextRenderer]::MeasureText($actionText, $toastAction.Font).Width + 24
    }
    $script:ToastActionBlock = $action
    $w = [math]::Min(520, 44 + $tw + $aw + 12)
    $toast.Width = $w
    $toastText.SetBounds(42, 0, ($w - 42 - $aw - 12), 48)
    if ($actionText) { $toastAction.SetBounds(($w - $aw - 8), 8, $aw, 32) }
    # canto de baixo da biblioteca (à esquerda do painel do jogo)
    $toast.Left = $libPanel.Right - $w - 18
    $script:ToastY = $bottom.Top - 48 - 14
    $toast.Top = $script:ToastY + 24
    $rp = New-RoundRect 0 0 $w 48 8
    $toast.Region = New-Object System.Drawing.Region($rp)
    $script:ToastTicks = 0
    $script:ToastLife = if ($actionText) { 6500 } else { 3200 }
    $toast.Visible = $true; $toast.BringToFront(); $toast.Invalidate()
    $toastTimer.Start()
}

# ---- tela "Abrindo jogo...": aparece enquanto o emulador carrega e some quando a janela do jogo abre
$script:LaunchOverlay = $null
function Show-LaunchOverlay($g, [string]$exe) {
    Close-LaunchOverlay
    if (-not $g) { return }
    $emu = switch -Wildcard ((Split-Path $exe -Leaf).ToLower()) {
        'pcsx2*' { 'PCSX2' } 'rpcs3*' { 'RPCS3' } 'shadps4*' { 'shadPS4' } default { 'emulador' }
    }
    if ($script:PlayFxOk) {
        try {
            $kind = Get-ConsoleKind $g
            $n = 4; if ($kind -eq 'PS2') { $n = 2 } elseif ($kind -eq 'PS3') { $n = 3 }
            $tint = @{ 2 = [System.Drawing.Color]::FromArgb(120, 170, 255); 3 = [System.Drawing.Color]::FromArgb(255, 110, 125); 4 = [System.Drawing.Color]::FromArgb(90, 175, 255) }[$n]
            $note = L "no $emu  •  a primeira vez pode demorar"
            $script:LaunchOverlay = [PL.PlayFx]::ShowGame($n, (Get-TriviumTitle $g), (L 'Abrindo jogo'), $note, (Get-DetailCover $g), $tint.ToArgb(), [System.Windows.Forms.Screen]::FromControl($form).Bounds)
            return
        } catch { Write-AppLog "Tela de carregamento: $($_.Exception.Message)" }
    }
    $ov = New-Object System.Windows.Forms.Form
    $ov.FormBorderStyle = 'None'; $ov.StartPosition = 'CenterScreen'; $ov.ShowInTaskbar = $false; $ov.TopMost = $true
    $ov.Size = New-Object System.Drawing.Size(520, 160); $ov.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 30)
    $ov.Region = New-Object System.Drawing.Region((New-RoundRect 0 0 520 160 14))
    [System.Windows.Forms.Form].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($ov, $true, $null)
    $ov.Tag = @{ game = $g; emu = $emu; cover = (Get-DetailCover $g); t = 0; start = Get-Date }
    $ov.Add_Paint({
            $o = $this.Tag
            $og = $_.Graphics
            $og.SmoothingMode = 'AntiAlias'; $og.InterpolationMode = 'HighQualityBicubic'; $og.TextRenderingHint = 'AntiAliasGridFit'
            $og.FillRectangle((New-Object System.Drawing.Drawing2D.LinearGradientBrush($this.ClientRectangle, [System.Drawing.Color]::FromArgb(40, 40, 52), [System.Drawing.Color]::FromArgb(20, 20, 26), 90)), $this.ClientRectangle)
            # capa pequena
            $cp = New-RoundRect 20 18 93 124 8
            $og.SetClip($cp); $og.DrawImage($o.cover, 20, 18, 93, 124); $og.ResetClip()
            $og.DrawPath((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 70, 82), 1)), $cp)
            $dots = '.' * (1 + [int]([math]::Floor($o.t / 20)) % 3)
            $og.DrawString((L ("Abrindo jogo$dots")), (New-Object System.Drawing.Font('Segoe UI', 10)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160, 160, 175))), 132, 26)
            $nameRect = New-Object System.Drawing.RectangleF(130, 48, 370, 52)
            $sfn = New-Object System.Drawing.StringFormat; $sfn.Trimming = 'EllipsisCharacter'
            $og.DrawString((L ($o.game.name)), (New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)), [System.Drawing.Brushes]::White, $nameRect, $sfn)
            $og.DrawString((L ("no $($o.emu)  •  a primeira vez pode demorar")), (New-Object System.Drawing.Font('Segoe UI', 9)), (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(130, 130, 145))), 132, 102)
            # barra que corre (não sabemos quanto falta)
            $bx = 132; $by = 130; $bw = 360
            $og.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(50, 50, 62))), $bx, $by, $bw, 4)
            $seg = 110
            $pos = ($o.t * 5) % ($bw + $seg) - $seg
            $x1 = [math]::Max($bx, $bx + $pos); $x2 = [math]::Min($bx + $bw, $bx + $pos + $seg)
            if ($x2 -gt $x1) { $og.FillRectangle((New-Object System.Drawing.SolidBrush($accent)), $x1, $by, $x2 - $x1, 4) }
        })
    $ovTimer = New-Object System.Windows.Forms.Timer
    $ovTimer.Interval = 30
    $ovTimer.Tag = $ov
    $ovTimer.Add_Tick({
            $o = $this.Tag
            if ($o.IsDisposed) { $this.Stop(); $this.Dispose(); return }
            $o.Tag.t++
            # o jogo não abriu janela própria (ex.: launcher externo): some depois de 40 s
            if (((Get-Date) - $o.Tag.start).TotalSeconds -gt 40) { Close-LaunchOverlay; return }
            $o.Invalidate()
        })
    $ov.Add_Click({ Close-LaunchOverlay })
    $script:LaunchOverlay = $ov
    $ov.Show()
    $ovTimer.Start()
}

function Release-LaunchOverlay([IntPtr]$win) {
    # a janela do shadPS4 fica escura alguns segundos antes do primeiro quadro: a animação segue por cima até lá
    $hold = $false
    try {
        if ($script:PlayFxOk -and $script:LaunchOverlay -and $script:RunGame -and (Get-ConsoleKind $script:RunGame) -eq 'PS4') {
            $script:OvHold = @{ log = (Join-Path (Get-Shadps4UserDir $script:RunEmuExe) 'log\shad_log.txt'); pos = [long]0; start = Get-Date; ready = $null; win = $win; expanded = $null }
            $ovHoldTimer.Start(); $hold = $true
        }
    } catch { Write-AppLog "Tela de carregamento: $($_.Exception.Message)" }
    if (-not $hold) { Close-LaunchOverlay }
}

$ovHoldTimer = New-Object System.Windows.Forms.Timer
$ovHoldTimer.Interval = 300
$ovHoldTimer.Add_Tick({
        $h = $script:OvHold; $ov = $script:LaunchOverlay
        if (-not $h) { $ovHoldTimer.Stop(); return }
        if (-not $ov -or $ov.IsDisposed) {
            # clicou para pular a animação: o jogo ainda precisa cobrir a tela
            $ovHoldTimer.Stop()
            if ($script:OvExpand -and -not $h.expanded -and $script:RunDir) { try { [PL.PlayFx]::MakeBorderless($h.win); [void][PL.Win]::SetForegroundWindow($h.win) } catch { Write-AppLog "Tela cheia: $($_.Exception.Message)" } }
            return
        }
        try {
            if (-not $h.ready) {
                $txt = ''
                $fs = [IO.File]::Open($h.log, 'Open', 'Read', 'ReadWrite, Delete')
                try {
                    if ($fs.Length -lt $h.pos) { $h.pos = 0 }
                    $n = [math]::Min($fs.Length - $h.pos, 8MB)
                    if ($n -gt 0) { $buf = New-Object byte[] $n; $fs.Position = $h.pos; $n = $fs.Read($buf, 0, $n); $h.pos += $n; $txt = [Text.Encoding]::GetEncoding(28591).GetString($buf, 0, $n) }
                } finally { $fs.Dispose() }
                # imagem final sendo preparada para a tela; jogo que não registra isso sai pelo tempo máximo
                if ($txt -match 'Display2DThin') { $h.ready = Get-Date }
                elseif (((Get-Date) - $h.start).TotalSeconds -gt 11) { $h.ready = (Get-Date).AddSeconds(-2) }
            }
        } catch { $h.ready = (Get-Date).AddSeconds(-2) }
        if (-not $h.ready -or ((Get-Date) - $h.ready).TotalSeconds -lt 1.4) { return }
        # primeiro cobre o monitor, ainda atrás da animação; ela só some depois que a imagem já se ajustou
        if (-not $h.expanded) {
            $h.expanded = Get-Date
            if ($script:OvExpand) {
                try { [PL.PlayFx]::MakeBorderless($h.win); [void][PL.Win]::SetForegroundWindow($h.win) } catch { Write-AppLog "Tela cheia: $($_.Exception.Message)" }
            }
            return
        }
        if (((Get-Date) - $h.expanded).TotalSeconds -ge 0.6) { $ovHoldTimer.Stop(); [PL.PlayFx]::Fade($ov) }
    })

function Close-LaunchOverlay {
    $ovHoldTimer.Stop()
    $ov = $script:LaunchOverlay
    $script:LaunchOverlay = $null
    if ($ov -and -not $ov.IsDisposed) { $ov.Close(); $ov.Dispose() }
}

# ---- "Continuar jogando": os últimos jogos abertos, numa faixa em cima da biblioteca
$recentBar = New-Object System.Windows.Forms.Panel
$recentBar.Dock = 'Top'; $recentBar.Height = 150; $recentBar.BackColor = $bg; $recentBar.Visible = $false
$recentTitle = New-Object System.Windows.Forms.Label
$recentTitle.Text = 'CONTINUAR JOGANDO'; $recentTitle.SetBounds(2, 0, 300, 18)
$recentTitle.Font = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold); $recentTitle.ForeColor = $dim
# resumo da biblioteca na mesma linha, à direita
$recentStats = New-Object System.Windows.Forms.Label
$recentStats.SetBounds(302, 0, 660, 18); $recentStats.TextAlign = 'TopRight'; $recentStats.ForeColor = $dim; $recentStats.Anchor = 'Top, Right'
$recentStats.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
$recentFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$recentFlow.SetBounds(0, 22, 2000, 116); $recentFlow.WrapContents = $false; $recentFlow.BackColor = $bg
$recentBar.Controls.AddRange(@($recentTitle, $recentStats, $recentFlow))
$recentBar.Add_Resize({ $recentStats.Left = [math]::Max(302, $this.ClientSize.Width - $recentStats.Width - 8) })
$fontRecentName = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$fontRecentInfo = New-Object System.Drawing.Font('Segoe UI', 8.5)
$RecentMax = 4

function New-RecentCard($g) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(250, 108); $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
    $card.Cursor = 'Hand'; $card.BackColor = $bg
    [System.Windows.Forms.Panel].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($card, $true, $null)
    $card.Tag = @{ game = $g; hot = $false }
    $card.Add_Paint({
            $t = $this.Tag; $rg = $_.Graphics
            $rg.SmoothingMode = 'AntiAlias'; $rg.InterpolationMode = 'HighQualityBicubic'
            $isSel = (Get-Selected) -and (Get-Selected).path -eq $t.game.path
            $fill = if ($t.hot) { [System.Drawing.Color]::FromArgb(48, 48, 60) } else { [System.Drawing.Color]::FromArgb(36, 36, 44) }
            $box = New-RoundRect 0 0 ($this.Width - 1) ($this.Height - 1) 10
            $rg.FillPath((New-Object System.Drawing.SolidBrush($fill)), $box)
            if ($isSel) { $rg.DrawPath((New-Object System.Drawing.Pen($accent, 2)), $box) }
            $key = Get-CoverImageKey $t.game
            $cp = New-RoundRect 8 8 69 92 6
            $rg.SetClip($cp)
            if ($imgGrid.Images.ContainsKey($key)) { $rg.DrawImage($imgGrid.Images[$key], 8, 8, 69, 92) }
            $rg.ResetClip()
            $tf = [System.Windows.Forms.TextFormatFlags]'WordBreak, EndEllipsis, NoPrefix'
            [System.Windows.Forms.TextRenderer]::DrawText($rg, (L ($t.game.name)), $fontRecentName, (New-Object System.Drawing.Rectangle(88, 12, 152, 40)), $fg, $tf)
            [System.Windows.Forms.TextRenderer]::DrawText($rg, (L ((Format-LastPlayed $t.game.lastPlayed))), $fontRecentInfo, (New-Object System.Drawing.Point(88, 58)), $dim)
            [System.Windows.Forms.TextRenderer]::DrawText($rg, (L ((Format-PlayTime ([int]$t.game.playSeconds)) + ' jogados')), $fontRecentInfo, (New-Object System.Drawing.Point(88, 76)), $dim)
        })
    $card.Add_MouseEnter({ $this.Tag.hot = $true; $this.Invalidate() })
    $card.Add_MouseLeave({ $this.Tag.hot = $false; $this.Invalidate() })
    $card.Add_Click({ [void](Select-Game $this.Tag.game) })
    $card.Add_DoubleClick({ if (Select-Game $this.Tag.game) { Play-Selected } })
    return $card
}

function Update-RecentStrip {
    # só na biblioteca sem busca; respeita a aba do console
    $recent = @()
    if (-not $txtSearch.Text.Trim()) {
        $recent = @($script:Cfg.games | Where-Object {
                $_.lastPlayed -and (Test-InTab $_ $script:ConsoleFilter)
            } | Sort-Object { $_.lastPlayed } -Descending | Select-Object -First $RecentMax)
    }
    $recentFlow.SuspendLayout()
    foreach ($c in @($recentFlow.Controls)) { $c.Dispose() }
    $recentFlow.Controls.Clear()
    foreach ($g in $recent) { $recentFlow.Controls.Add((New-RecentCard $g)) }
    $recentFlow.ResumeLayout()
    $recentBar.Visible = $recent.Count -gt 0
    $secs = 0; foreach ($g in $script:Cfg.games) { $secs += [int]$g.playSeconds }
    $count = @($script:Cfg.games).Count
    $recentStats.Text = "$count $(if ($count -eq 1) { L 'jogo na biblioteca' } else { L 'jogos na biblioteca' })   •   $(L ((Format-PlayTime $secs) + ' jogados'))"
}
$lv.Add_SelectedIndexChanged({ foreach ($c in $recentFlow.Controls) { $c.Invalidate() } })

# ---- controle navegando pelo launcher
# XInput: Xbox (ou PlayStation pelo Steam/DS4Windows). Controle de PlayStation ligado direto (DualShock 4,
# DualSense) não aparece no XInput: é lido como joystick do Windows (winmm) e os botões viram os mesmos do Xbox.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PL {
    public static class Pad {
        [StructLayout(LayoutKind.Sequential)]
        struct XState { public uint Packet; public ushort Buttons; public byte LT; public byte RT; public short LX; public short LY; public short RX; public short RY; }
        [DllImport("xinput1_4.dll")] static extern int XInputGetState(int index, out XState state);
        [StructLayout(LayoutKind.Sequential)]
        struct JoyInfo { public int dwSize, dwFlags, dwXpos, dwYpos, dwZpos, dwRpos, dwUpos, dwVpos, dwButtons, dwButtonNumber, dwPOV, dwReserved1, dwReserved2; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct JoyCaps {
            public ushort wMid; public ushort wPid;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szPname;
            public int wXmin, wXmax, wYmin, wYmax, wZmin, wZmax, wNumButtons, wPeriodMin, wPeriodMax, wRmin, wRmax, wUmin, wUmax, wVmin, wVmax, wCaps, wMaxAxes, wNumAxes, wMaxButtons;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szRegKey;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szOEMVxD;
        }
        [DllImport("winmm.dll")] static extern int joyGetPosEx(int id, ref JoyInfo ji);
        [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int joyGetDevCapsW(IntPtr id, ref JoyCaps caps, int size);

        static int connected = -1;          // controles XInput achados na última busca (bits)
        static int sony = 0;                // joysticks da Sony (bits do id do winmm)
        static DateTime lastScan = DateTime.MinValue;
        public static bool Available = true;
        public static bool JoyAvailable = true;

        // botões juntando todos os controles; o analógico esquerdo também vale como direcional
        public static int Read() {
            bool scan = (connected <= 0 && sony == 0) && (DateTime.Now - lastScan).TotalSeconds > 2;
            if (connected <= 0 && sony == 0 && !scan) return 0;
            if (scan) lastScan = DateTime.Now;
            return ReadXInput(scan) | ReadSony(scan);
        }

        static int ReadXInput(bool scan) {
            if (!Available) return 0;
            int result = 0, found = 0;
            for (int i = 0; i < 4; i++) {
                if (!scan && (connected & (1 << i)) == 0) continue;
                XState s;
                try { if (XInputGetState(i, out s) != 0) continue; } catch { Available = false; return 0; }
                found |= 1 << i;
                int b = s.Buttons;
                if (s.LY > 16000) b |= 0x1; if (s.LY < -16000) b |= 0x2;
                if (s.LX < -16000) b |= 0x4; if (s.LX > 16000) b |= 0x8;
                result |= b;
            }
            if (scan || found != connected) connected = found;
            return result;
        }

        static int ReadSony(bool scan) {
            if (!JoyAvailable) return 0;
            try {
                if (scan) {
                    // só controles da Sony (VID 054C): os de Xbox já vêm pelo XInput, com outra ordem de botões
                    sony = 0;
                    for (int i = 0; i < 16; i++) {
                        JoyCaps c = new JoyCaps();
                        if (joyGetDevCapsW((IntPtr)i, ref c, Marshal.SizeOf(typeof(JoyCaps))) == 0 && c.wMid == 0x054C) sony |= 1 << i;
                    }
                }
                int result = 0;
                for (int i = 0; i < 16; i++) {
                    if ((sony & (1 << i)) == 0) continue;
                    JoyInfo j = new JoyInfo();
                    j.dwSize = Marshal.SizeOf(typeof(JoyInfo)); j.dwFlags = 0xFF;   // JOY_RETURNALL
                    if (joyGetPosEx(i, ref j) != 0) { sony &= ~(1 << i); continue; }   // desconectou
                    int d = j.dwButtons, b = 0;
                    // DualShock 4 / DualSense: Quadrado, X, Bolinha, Triângulo, L1, R1, L2, R2, Share, Options...
                    if ((d & 0x002) != 0) b |= 0x1000;   // X (Cruz)  -> A
                    if ((d & 0x004) != 0) b |= 0x2000;   // Bolinha   -> B
                    if ((d & 0x001) != 0) b |= 0x4000;   // Quadrado  -> X
                    if ((d & 0x008) != 0) b |= 0x8000;   // Triângulo -> Y
                    if ((d & 0x010) != 0) b |= 0x0100;   // L1 -> LB
                    if ((d & 0x020) != 0) b |= 0x0200;   // R1 -> RB
                    if ((d & 0x100) != 0) b |= 0x0020;   // Share/Create -> Back
                    if ((d & 0x200) != 0) b |= 0x0010;   // Options -> Start
                    // direcional (POV em centésimos de grau; 65535 = solto) e analógico esquerdo
                    int pov = j.dwPOV;
                    if (pov >= 0 && pov < 36000) {
                        if (pov >= 31500 || pov <= 4500) b |= 0x1;
                        if (pov >= 4500 && pov <= 13500) b |= 0x8;
                        if (pov >= 13500 && pov <= 22500) b |= 0x2;
                        if (pov >= 22500 && pov <= 31500) b |= 0x4;
                    }
                    if (j.dwYpos < 12000) b |= 0x1; if (j.dwYpos > 53500) b |= 0x2;
                    if (j.dwXpos < 12000) b |= 0x4; if (j.dwXpos > 53500) b |= 0x8;
                    result |= b;
                }
                return result;
            } catch { JoyAvailable = false; return 0; }
        }

        public static bool Connected { get { return connected > 0 || sony != 0; } }
    }
}
'@
$script:PadPrev = 0; $script:PadHeld = 0; $script:PadWasConnected = $false
$padTimer = New-Object System.Windows.Forms.Timer
$padTimer.Interval = 50
$padTimer.Add_Tick({
        $tvOn = $script:TvForm -and $script:TvForm.Visible -and [System.Windows.Forms.Form]::ActiveForm -eq $script:TvForm
        if ($script:RunDir -or ([System.Windows.Forms.Form]::ActiveForm -ne $form -and -not $tvOn)) { $script:PadPrev = 0; return }
        $b = [PL.Pad]::Read()
        if ($tvOn) {
            # modo TV: esquerda/direita escolhe, A/Start joga, Y configura, X favorito, B/Back sai, LB/RB troca o console
            $new = $b -band -bnot $script:PadPrev; $script:PadPrev = $b
            $dir = $b -band 0xC
            if ($dir) { $script:PadHeld++ } else { $script:PadHeld = 0 }
            if ($dir -and ($script:PadHeld -eq 1 -or ($script:PadHeld -gt 8 -and $script:PadHeld % 2 -eq 0))) { if ($dir -band 0x4) { Step-TvSelection -1 } else { Step-TvSelection 1 } }
            if ($new -band 0x1000 -or $new -band 0x10) { Start-TvGame }
            elseif ($new -band 0x8000) { Open-TvSettings }
            elseif ($new -band 0x4000) { Switch-TvFavorite }
            elseif ($new -band 0x2000 -or $new -band 0x20) { Close-TvMode }
            elseif ($new -band 0x100) { Step-TvFilter -1 }
            elseif ($new -band 0x200) { Step-TvFilter 1 }
            return
        }
        if (($b -band -bnot $script:PadPrev) -band 0x20) { $script:PadPrev = $b; Show-TvMode; return }   # Back/Select: modo TV
        if ([PL.Pad]::Connected -and -not $script:PadWasConnected) { Show-Toast 'Controle conectado: direcional navega, A/X joga, Y/Triângulo configura, LB/RB trocam a aba' 'ok' }
        $script:PadWasConnected = [PL.Pad]::Connected
        $new = $b -band -bnot $script:PadPrev
        $script:PadPrev = $b
        # direcional: na hora e repetindo se segurar
        $dir = $b -band 0xF
        if ($dir) { $script:PadHeld++ } else { $script:PadHeld = 0 }
        if ($dir -and ($script:PadHeld -eq 1 -or ($script:PadHeld -gt 8 -and $script:PadHeld % 3 -eq 0))) {
            if ($dir -band 0x1) { Move-Selection 'Up' } elseif ($dir -band 0x2) { Move-Selection 'Down' }
            elseif ($dir -band 0x4) { Move-Selection 'Left' } elseif ($dir -band 0x8) { Move-Selection 'Right' }
        }
        if ($new -band 0x1000 -or $new -band 0x10) { Play-Selected }                  # A (X no PlayStation) ou Start
        elseif ($new -band 0x8000) { if (-not $script:TrophyMode) { Invoke-GameSettings } }   # Y (Triângulo)
        elseif ($new -band 0x2000) { if ($txtSearch.Text) { $txtSearch.Text = '' } }  # B (Bolinha): limpa a busca
        elseif ($new -band 0x4000) { $sg = Get-Selected; if ($sg -and -not $script:TrophyMode) { Set-Favorite $sg (-not $sg.favorite) } }   # X (Quadrado): favorito
        elseif ($new -band 0x100) { Step-ConsoleTab -1 }                              # LB / L1
        elseif ($new -band 0x200) { Step-ConsoleTab 1 }                               # RB / R1
    })

function Move-Selection([string]$where) {
    if ($script:TrophyMode) {
        # na aba Conquistas: cima/baixo trocam de jogo
        $n = $trGames.Items.Count
        if ($n -eq 0) { return }
        $i = $trGames.SelectedIndex
        if ($where -in 'Up', 'Left') { $i-- } else { $i++ }
        $trGames.SelectedIndex = [math]::Max(0, [math]::Min($n - 1, $i))
        return
    }
    if ($lv.Items.Count -eq 0) { return }
    $cur = $null; if ($lv.SelectedItems.Count) { $cur = $lv.SelectedItems[0] }
    if (-not $cur) { $next = $lv.Items[0] }
    elseif ($lv.View -eq 'Details') {
        $i = $cur.Index
        if ($where -in 'Up', 'Left') { $i-- } else { $i++ }
        $next = $null; if ($i -ge 0 -and $i -lt $lv.Items.Count) { $next = $lv.Items[$i] }
    } else {
        $next = $lv.FindNearestItem([System.Windows.Forms.SearchDirectionHint]$where, $cur.Position)
    }
    if (-not $next) { return }
    $cur.Selected = $false
    $next.Selected = $true; $next.Focused = $true; $next.EnsureVisible()
}

function Step-ConsoleTab([int]$step) {
    $names = @($TabNames) + 'Conquistas'
    $cur = $script:ConsoleFilter; if ($script:TrophyMode) { $cur = 'Conquistas' }
    $i = [array]::IndexOf($names, $cur) + $step
    if ($i -lt 0) { $i = $names.Count - 1 } elseif ($i -ge $names.Count) { $i = 0 }
    if ($names[$i] -eq 'Conquistas') { Show-TrophyView } else { Set-ConsoleFilter $names[$i] }
}

# ---- menu do botão direito na capa
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System.Drawing;
using System.Windows.Forms;
namespace PL {
    // cores escuras para o menu (o padrão do Windows é claro)
    public class DarkMenuColors : ProfessionalColorTable {
        static Color Bg = Color.FromArgb(40, 40, 48), Hover = Color.FromArgb(62, 62, 76), Line = Color.FromArgb(70, 70, 82);
        public override Color ToolStripDropDownBackground { get { return Bg; } }
        public override Color ImageMarginGradientBegin { get { return Bg; } }
        public override Color ImageMarginGradientMiddle { get { return Bg; } }
        public override Color ImageMarginGradientEnd { get { return Bg; } }
        public override Color MenuBorder { get { return Line; } }
        public override Color MenuItemBorder { get { return Hover; } }
        public override Color MenuItemSelected { get { return Hover; } }
        public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
        public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
        public override Color SeparatorDark { get { return Line; } }
        public override Color SeparatorLight { get { return Bg; } }
    }
}
'@
$gameMenu = New-Object System.Windows.Forms.ContextMenuStrip
$gameMenu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object PL.DarkMenuColors))
$gameMenu.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 48); $gameMenu.ForeColor = $fg
$gameMenu.Font = New-Object System.Drawing.Font('Segoe UI', 10); $gameMenu.ShowImageMargin = $true
$gameMenu.ImageScalingSize = New-Object System.Drawing.Size(20, 20)

function Add-MenuItem([string]$text, [int]$glyphCode, [scriptblock]$onClick, [string]$keys = '') {
    # ($glyphCode, não $glyph: o PowerShell não diferencia maiúsculas e $glyph apagaria a tabela $Glyph)
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem($text)
    $mi.Image = New-GlyphImage $glyphCode 14 $fg
    $mi.ForeColor = $fg; $mi.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    if ($keys) { $mi.ShortcutKeyDisplayString = $keys }
    $mi.Add_Click($onClick)
    [void]$gameMenu.Items.Add($mi)
    return $mi
}
$miPlay = Add-MenuItem 'Jogar' $Glyph.play { Play-Selected } 'Enter'
$miPlay.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
[void](Add-MenuItem 'Configurar' $Glyph.settings { Invoke-GameSettings } 'F2')
[void](Add-MenuItem 'Abrir pasta do jogo' $Glyph.folder { $dtBtnDir.PerformClick() })
# PS2: pacote de texturas HD do PCSX2 (a mesma tela do botão "Texturas HD..." em Configurar)
$miTex = Add-MenuItem 'Texturas HD...' 0xE790 { $g = Get-Selected; if ($g) { Show-TexturesDialog $g $form } }
[void]$gameMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miFav = Add-MenuItem 'Adicionar aos favoritos' $Glyph.star { $g = Get-Selected; if ($g) { Set-Favorite $g (-not $g.favorite) } } 'Ctrl+D'
$miFav.Image = New-GlyphImage $Glyph.star 14 $FavColor
[void](Add-MenuItem 'Trocar capa...' 0xEB9F { $g = Get-Selected; if ($g) { Set-CustomCover $g } })
$miCoverReset = Add-MenuItem 'Voltar à capa original' 0xE7A7 { $g = Get-Selected; if ($g) { Reset-CustomCover $g } }
[void](Add-MenuItem 'Renomear...' 0xE8AC { $g = Get-Selected; if ($g) { Rename-Game $g } })
[void]$gameMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miRemove = Add-MenuItem 'Remover da lista' $Glyph.remove { Invoke-RemoveGame } 'Delete'
$miRemove.ForeColor = [System.Drawing.Color]::FromArgb(255, 150, 140)
$gameMenu.Add_Opening({
        $g = Get-Selected
        if (-not $g) { $_.Cancel = $true; return }
        $miCoverReset.Visible = [bool]$g.cover
        $miTex.Visible = ($g.console -eq 'PS2')
        if ($g.favorite) { $miFav.Text = 'Remover dos favoritos' } else { $miFav.Text = 'Adicionar aos favoritos' }
    })

# menu de ordenar (mesmo visual escuro)
$sortMenu = New-Object System.Windows.Forms.ContextMenuStrip
$sortMenu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object PL.DarkMenuColors))
$sortMenu.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 48); $sortMenu.ForeColor = $fg
$sortMenu.Font = New-Object System.Drawing.Font('Segoe UI', 10)
foreach ($sk in $SortModes.Keys) {
    $smi = New-Object System.Windows.Forms.ToolStripMenuItem($SortModes[$sk])
    $smi.Tag = $sk; $smi.ForeColor = $fg; $smi.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $smi.Add_Click({ Set-SortMode $this.Tag; $script:Cfg.sortMode = $this.Tag; Save-Config; Refresh-List })
    [void]$sortMenu.Items.Add($smi)
}
$sortMenu.Add_Opening({ foreach ($it in $sortMenu.Items) { $it.Checked = $it.Tag -eq $script:SortMode } })

# clique direito: escolhe o jogo embaixo do mouse e abre o menu
$lv.Add_MouseUp({
        if ($_.Button -ne 'Right') { return }
        $hit = $lv.HitTest($_.Location).Item
        if (-not $hit) { return }
        if (-not $hit.Selected) { foreach ($it in $lv.SelectedItems) { $it.Selected = $false }; $hit.Selected = $true; $hit.Focused = $true }
        $gameMenu.Show($lv, $_.Location)
    })
# também nas capas de "Continuar jogando" e na capa grande do painel
$recentFlow.Add_ControlAdded({
        $_.Control.Add_MouseUp({
                if ($_.Button -ne 'Right') { return }
                if (Select-Game $this.Tag.game) { $gameMenu.Show($this, $_.Location) }
            })
    })
$dtCover.ContextMenuStrip = $gameMenu
# Shift+F10 / tecla de menu no teclado
$lv.Add_KeyDown({
        if (($_.KeyCode -eq 'Apps' -or ($_.Shift -and $_.KeyCode -eq 'F10')) -and $lv.SelectedItems.Count) {
            $r = $lv.SelectedItems[0].Bounds
            $gameMenu.Show($lv, (New-Object System.Drawing.Point(($r.X + 20), ($r.Y + 40))))
            $_.SuppressKeyPress = $true
        }
    })

function Clear-CoverCache($g) {
    # tira as imagens antigas deste jogo da memória para redesenhar com a capa nova
    foreach ($k in @($script:CoverKeys[$g.path], [IO.Path]::GetFileNameWithoutExtension([string]$g.cover)) | Where-Object { $_ }) {
        if ($imgCovers.Images.ContainsKey($k)) { $imgCovers.Images.RemoveByKey($k) }
        if ($imgGrid.Images.ContainsKey($k)) { $imgGrid.Images.RemoveByKey($k) }
        $script:DetailCovers.Remove($k); $script:DetailBackdrops.Remove($k)
    }
}

function Set-CustomCover($g) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = L "Escolha a capa de $($g.name)"
    $dlg.Filter = L 'Imagens|*.png;*.jpg;*.jpeg;*.bmp;*.gif|Todos|*.*'
    if ($dlg.ShowDialog($form) -ne 'OK') { return }
    New-Item -ItemType Directory -Force $CoverDir | Out-Null
    $old = $g.cover
    $name = 'custom_' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '.png'
    if (-not (Save-CoverFile ([IO.File]::ReadAllBytes($dlg.FileName)) (Join-Path $CoverDir $name))) {
        Show-Toast 'Não foi possível abrir essa imagem' 'warn'; return
    }
    Clear-CoverCache $g
    if ($old) { Remove-Item -LiteralPath (Join-Path $CoverDir $old) -ErrorAction SilentlyContinue }
    $g | Add-Member -NotePropertyName cover -NotePropertyValue $name -Force
    Save-Config; Refresh-List; [void](Select-Game $g)
    Show-Toast 'Capa trocada' 'ok'
}

function Reset-CustomCover($g) {
    if (-not $g.cover) { return }
    Clear-CoverCache $g
    Remove-Item -LiteralPath (Join-Path $CoverDir $g.cover) -ErrorAction SilentlyContinue
    $g.PSObject.Properties.Remove('cover')
    Save-Config; Refresh-List; [void](Select-Game $g)
    Show-Toast 'Capa original de volta' 'ok'
}

function Rename-Game($g) {
    $d = New-Dialog 'Renomear jogo' 520 170
    $l = New-Label 'Nome que aparece na biblioteca' 22 18 $dim
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.SetBounds(22, 44, 476, 30); $tb.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $tb.BackColor = $panelBg; $tb.ForeColor = $fg; $tb.BorderStyle = 'FixedSingle'; $tb.Text = $g.name
    $bOk = New-Button 'Salvar' 282 106 104 40; $bOk.BackColor = $accent; $bOk.Font = $fontBold; $bOk.FlatAppearance.BorderSize = 0; $bOk.DialogResult = 'OK'
    $bNo = New-Button 'Cancelar' 394 106 104 40; $bNo.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($l, $tb, $bOk, $bNo)); $d.AcceptButton = $bOk; $d.CancelButton = $bNo
    $d.Tag = $tb
    $d.Add_Shown({ $this.Tag.SelectAll(); [void]$this.Tag.Focus() })
    if ($d.ShowDialog($form) -ne 'OK') { return }
    $new = $tb.Text.Trim()
    if (-not $new -or $new -eq $g.name) { return }
    $g.name = $new
    Save-Config; Refresh-List; [void](Select-Game $g)
    Show-Toast "Renomeado para $new" 'ok'
}

# ---- aba Conquistas: troféus de todos os consoles no estilo do PS5
# (nível e total no topo, jogos com o progresso à esquerda, troféus do jogo escolhido à direita)
$script:TrophySets = @()
$script:TrImg = @{}
$script:TrFilter = 'todos'
$script:RaJob = $null; $script:RaError = ''; $script:RaLastFetch = $null
$fontTrLevel = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
$fontTrNum = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$fontTrGame = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$fontTrSmall = New-Object System.Drawing.Font('Segoe UI', 9)
$fontTrLock = New-Object System.Drawing.Font('Segoe MDL2 Assets', 20)
$TrTextFlags = [System.Windows.Forms.TextFormatFlags]'EndEllipsis, NoPrefix, SingleLine, VerticalCenter'
$TrTrack = [System.Drawing.Color]::FromArgb(58, 58, 70)

function Set-DoubleBuffered($ctl) {
    $ctl.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($ctl, $true, $null)
}

function Get-TrophyImage([string]$path, [int]$w, [int]$h, [bool]$locked) {
    # imagem já reduzida para o tamanho do desenho; troféu não conquistado fica cinza e apagado
    $k = "$path|$w|$h|$locked"
    if ($script:TrImg.ContainsKey($k)) { return $script:TrImg[$k] }
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($path))
        $src = [System.Drawing.Image]::FromStream($ms)
        $sc = [math]::Min($w / $src.Width, $h / $src.Height)
        $dw = [int]($src.Width * $sc); $dh = [int]($src.Height * $sc)
        $out = New-Object System.Drawing.Bitmap($w, $h)
        $gr = [System.Drawing.Graphics]::FromImage($out)
        $gr.InterpolationMode = 'HighQualityBicubic'
        $dst = New-Object System.Drawing.Rectangle([int](($w - $dw) / 2), [int](($h - $dh) / 2), $dw, $dh)
        if ($locked) {
            $cm = New-Object System.Drawing.Imaging.ColorMatrix
            $cm.Matrix00 = 0.3; $cm.Matrix01 = 0.3; $cm.Matrix02 = 0.3
            $cm.Matrix10 = 0.59; $cm.Matrix11 = 0.59; $cm.Matrix12 = 0.59
            $cm.Matrix20 = 0.11; $cm.Matrix21 = 0.11; $cm.Matrix22 = 0.11
            $cm.Matrix33 = 0.4
            $ia = New-Object System.Drawing.Imaging.ImageAttributes
            $ia.SetColorMatrix($cm)
            $gr.DrawImage($src, $dst, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
        } else { $gr.DrawImage($src, $dst) }
        $gr.Dispose(); $src.Dispose()
        $script:TrImg[$k] = $out
        return $out
    } catch { return $null }
}

function Draw-TrophyBar($gr, [int]$x, [int]$y, [int]$w, [int]$h, [int]$pct, $color) {
    $gr.FillPath((New-Object System.Drawing.SolidBrush($TrTrack)), (New-RoundRect $x $y $w $h ($h / 2)))
    $fw = [int]($w * $pct / 100)
    if ($fw -ge $h) { $gr.FillPath((New-Object System.Drawing.SolidBrush($color)), (New-RoundRect $x $y $fw $h ($h / 2))) }
}

function Draw-GradeCounts($gr, $set, [int]$x, [int]$y, [int]$size, [bool]$showTotal) {
    # taças coloridas com a quantidade de cada tipo (só os tipos que o jogo tem)
    foreach ($gd in $TrophyGrades) {
        if ($set.totals[$gd] -eq 0) { continue }
        Draw-TrophyCup $gr $x $y $size $TrophyColors[$gd]
        $txt = [string]$set.counts[$gd]; if ($showTotal) { $txt += "/$($set.totals[$gd])" }
        $tw = [System.Windows.Forms.TextRenderer]::MeasureText($txt, $fontTrSmall).Width
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($txt)), $fontTrSmall, (New-Object System.Drawing.Rectangle(($x + $size + 2), ($y - 2), ($tw + 4), ($size + 4))), $fg, $TrTextFlags)
        $x += $size + $tw + 14
    }
}

$trophyView = New-Object System.Windows.Forms.Panel
$trophyView.Dock = 'Fill'; $trophyView.BackColor = $bg; $trophyView.Visible = $false

# topo: nível de troféus, total de cada tipo e o estado do RetroAchievements
$trHead = New-Object System.Windows.Forms.Panel
$trHead.Dock = 'Top'; $trHead.Height = 96; $trHead.BackColor = $bg
Set-DoubleBuffered $trHead
$trHead.Add_Paint({
        $gr = $_.Graphics; $gr.SmoothingMode = 'AntiAlias'; $gr.TextRenderingHint = 'ClearTypeGridFit'
        $tot = @{ P = 0; G = 0; S = 0; B = 0 }; $pts = 0
        foreach ($s in $script:TrophySets) { foreach ($gd in $TrophyGrades) { $tot[$gd] += $s.counts[$gd]; $pts += $s.counts[$gd] * $TrophyPoints[$gd] } }
        $lv0 = Get-TrophyLevel $pts
        # anel do nível (enche conforme os pontos para o próximo)
        $cx = 20; $cy = 14; $d = 66
        $gr.DrawEllipse((New-Object System.Drawing.Pen($TrTrack, 5)), $cx, $cy, $d, $d)
        $sweep = [single](360 * $lv0.have / $lv0.need)
        if ($sweep -gt 0) { $gr.DrawArc((New-Object System.Drawing.Pen($accent, 5)), $cx, $cy, $d, $d, -90, $sweep) }
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $gr.DrawString((L ([string]$lv0.level)), $fontTrLevel, (New-Object System.Drawing.SolidBrush($fg)), (New-RectF $cx ($cy + 1) $d $d), $sf)
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ('Nível de troféus')), $fontBold, (New-Object System.Drawing.Point(100, 22)), $fg)
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ("$($lv0.have) de $($lv0.need) pontos para o nível $($lv0.level + 1)")), $fontTrSmall, (New-Object System.Drawing.Point(101, 46)), $dim)
        # total por tipo
        $x = 330
        foreach ($gd in $TrophyGrades) {
            Draw-TrophyCup $gr $x 22 30 $TrophyColors[$gd]
            [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ([string]$tot[$gd])), $fontTrNum, (New-Object System.Drawing.Point(($x + 36), 16)), $fg)
            [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($TrophyNames[$gd])), $fontTrSmall, (New-Object System.Drawing.Point(($x + 37), 44)), $dim)
            $x += 108
        }
        $gr.DrawLine((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50, 50, 60))), 18, $this.Height - 1, $this.Width - 18, $this.Height - 1)
    })
$trBtnAcc = New-Button '  Contas e opções' 0 0 168 34
$trBtnAcc.Image = New-GlyphImage $Glyph.settings 14 $fg; $trBtnAcc.TextImageRelation = 'ImageBeforeText'
$trBtnAcc.Anchor = 'Top, Right'; $trBtnAcc.Cursor = 'Hand'
$trBtnRef = New-Button '  Atualizar' 0 0 116 34
$trBtnRef.Image = New-GlyphImage 0xE72C 14 $fg; $trBtnRef.TextImageRelation = 'ImageBeforeText'
$trBtnRef.Anchor = 'Top, Right'; $trBtnRef.Cursor = 'Hand'
$trStatus = New-Label '' 0 0 $dim
$trStatus.AutoSize = $false; $trStatus.TextAlign = 'MiddleRight'; $trStatus.Anchor = 'Top, Right'; $trStatus.Font = $fontTrSmall
$trHead.Controls.AddRange(@($trBtnAcc, $trBtnRef, $trStatus))
$trHead.Add_Resize({
        $trBtnAcc.Left = $this.ClientSize.Width - $trBtnAcc.Width - 18; $trBtnAcc.Top = 16
        $trBtnRef.Left = $trBtnAcc.Left - $trBtnRef.Width - 8; $trBtnRef.Top = 16
        $trStatus.Width = 420; $trStatus.Height = 20
        $trStatus.Left = $this.ClientSize.Width - $trStatus.Width - 18; $trStatus.Top = 58
    })

$trBody = New-Object System.Windows.Forms.Panel
$trBody.Dock = 'Fill'; $trBody.BackColor = $bg
$trBody.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 8)

function New-TrophyListBox([int]$itemH) {
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.DrawMode = 'OwnerDrawFixed'; $lb.ItemHeight = $itemH; $lb.IntegralHeight = $false
    $lb.BorderStyle = 'None'; $lb.BackColor = $bg; $lb.ForeColor = $fg
    Set-DoubleBuffered $lb
    return $lb
}

# esquerda: jogos com troféus
$trGames = New-TrophyListBox 92
$trGames.Dock = 'Left'; $trGames.Width = 420
$trGames.Add_DrawItem({
        $e = $_
        if ($e.Index -lt 0 -or $e.Index -ge $this.Items.Count) { return }
        $set = $this.Items[$e.Index]; $gr = $e.Graphics; $r = $e.Bounds
        $gr.SmoothingMode = 'AntiAlias'; $gr.InterpolationMode = 'HighQualityBicubic'
        $gr.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $r)
        $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $card = New-RoundRect ($r.X + 2) ($r.Y + 4) ($r.Width - 10) ($r.Height - 8) 10
        $cb = $panelBg; if ($sel) { $cb = [System.Drawing.Color]::FromArgb(46, 52, 74) }
        $gr.FillPath((New-Object System.Drawing.SolidBrush($cb)), $card)
        if ($sel) { $gr.DrawPath((New-Object System.Drawing.Pen($accent, 2)), $card) }
        $ix = $r.X + 14; $iy = $r.Y + 16
        $img = Get-TrophyImage $set.icon 108 60 $false
        if ($img) { $gr.DrawImage($img, $ix, $iy) }
        else {
            $gr.FillPath((New-Object System.Drawing.SolidBrush($TrTrack)), (New-RoundRect $ix $iy 108 60 6))
            Draw-TrophyCup $gr ($ix + 38) ($iy + 13) 32 $dim
        }
        $tx = $ix + 122; $tw = $r.Right - $tx - 20
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($set.title)), $fontBold, (New-Object System.Drawing.Rectangle($tx, ($r.Y + 12), $tw, 22)), $fg, $TrTextFlags)
        $cc = $dim; if ($consoleColors.ContainsKey($set.platform)) { $cc = $consoleColors[$set.platform] }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($set.platform)), $fontTrSmall, (New-Object System.Drawing.Rectangle($tx, ($r.Y + 35), 34, 18)), $cc, $TrTextFlags)
        Draw-GradeCounts $gr $set ($tx + 36) ($r.Y + 37) 13 $false
        $barColor = $accent; if ($set.pct -ge 100) { $barColor = $TrophyColors.P }
        Draw-TrophyBar $gr $tx ($r.Y + 64) ($tw - 46) 6 $set.pct $barColor
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ("$($set.pct)%")), $fontTrSmall, (New-Object System.Drawing.Rectangle(($tx + $tw - 42), ($r.Y + 57), 44, 20)), $fg, $TrTextFlags)
    })
$trGames.Add_SelectedIndexChanged({ Update-TrophyList })

$trGap = New-Object System.Windows.Forms.Panel
$trGap.Dock = 'Left'; $trGap.Width = 14; $trGap.BackColor = $bg

# direita: cabeçalho do jogo + filtro + lista de troféus
$trRight = New-Object System.Windows.Forms.Panel
$trRight.Dock = 'Fill'; $trRight.BackColor = $bg

$trGameHead = New-Object System.Windows.Forms.Panel
$trGameHead.Dock = 'Top'; $trGameHead.Height = 158; $trGameHead.BackColor = $bg
Set-DoubleBuffered $trGameHead
$trGameHead.Add_Paint({
        $set = $trGames.SelectedItem
        if (-not $set) { return }
        $gr = $_.Graphics; $gr.SmoothingMode = 'AntiAlias'; $gr.InterpolationMode = 'HighQualityBicubic'
        $img = Get-TrophyImage $set.icon 186 102 $false
        if ($img) { $gr.DrawImage($img, 4, 6) }
        $tx = 206; $tw = $this.ClientSize.Width - $tx - 8
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($set.title)), $fontTrGame, (New-Object System.Drawing.Rectangle($tx, 4, $tw, 32)), $fg, $TrTextFlags)
        $cc = $dim; if ($consoleColors.ContainsKey($set.platform)) { $cc = $consoleColors[$set.platform] }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($set.platform)), $fontBold, (New-Object System.Drawing.Point(($tx + 1), 40)), $cc)
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ("$($set.earned) de $($set.total) conquistados")), $font, (New-Object System.Drawing.Point(($tx + 44), 40)), $dim)
        $barColor = $accent; if ($set.pct -ge 100) { $barColor = $TrophyColors.P }
        Draw-TrophyBar $gr ($tx + 1) 72 ([math]::Min(360, $tw - 60)) 8 ([int]($set.pct * (Get-Eased $script:TrBar))) $barColor
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ("$($set.pct)%")), $fontBold, (New-Object System.Drawing.Point(($tx + [math]::Min(360, $tw - 60) + 10), 64)), $fg)
        Draw-GradeCounts $gr $set ($tx + 1) 92 16 $true
    })

$trFilters = New-Object System.Windows.Forms.FlowLayoutPanel
$trFilters.Dock = 'Bottom'; $trFilters.Height = 40; $trFilters.BackColor = $bg; $trFilters.WrapContents = $false
$trFilters.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
$script:TrFilterButtons = [ordered]@{}
foreach ($fk in 'todos', 'ganhos', 'faltam') {
    $fb = New-Object System.Windows.Forms.Button
    $fb.Tag = $fk; $fb.Height = 30; $fb.FlatStyle = 'Flat'; $fb.Cursor = 'Hand'; $fb.Font = $font
    $fb.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(62, 62, 74)
    $fb.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(58, 58, 70)
    $fb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $fb.Add_Click({ $script:TrFilter = $this.Tag; Update-TrophyList })
    $script:TrFilterButtons[$fk] = $fb
    $trFilters.Controls.Add($fb)
}
$trGameHead.Controls.Add($trFilters)

$trList = New-TrophyListBox 80
$trList.Dock = 'Fill'
$trList.Add_DrawItem({
        $e = $_
        if ($e.Index -lt 0 -or $e.Index -ge $this.Items.Count) { return }
        $t = $this.Items[$e.Index]; $gr = $e.Graphics; $r = $e.Bounds
        $gr.SmoothingMode = 'AntiAlias'; $gr.TextRenderingHint = 'ClearTypeGridFit'
        $gr.FillRectangle((New-Object System.Drawing.SolidBrush($bg)), $r)
        $card = New-RoundRect ($r.X + 2) ($r.Y + 3) ($r.Width - 10) ($r.Height - 6) 10
        $gr.FillPath((New-Object System.Drawing.SolidBrush($panelBg)), $card)
        $secret = $t.hidden -and -not $t.earned
        # ícone do troféu (cinza enquanto não conquistado; cadeado se for oculto)
        $ix = $r.X + 12; $iy = $r.Y + 11
        $img = $null; if (-not $secret) { $img = Get-TrophyImage $t.icon 58 58 (-not $t.earned) }
        if ($img) { $gr.DrawImage($img, $ix, $iy) }
        else {
            $gr.FillPath((New-Object System.Drawing.SolidBrush($TrTrack)), (New-RoundRect $ix $iy 58 58 8))
            if ($secret) {
                $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
                $gr.DrawString([string][char]0xE72E, $fontTrLock, (New-Object System.Drawing.SolidBrush($dim)), (New-RectF $ix $iy 58 58), $sf)
            } else {
                $c = $TrophyColors[$t.grade]; if (-not $t.earned) { $c = [System.Drawing.Color]::FromArgb(110, $c) }
                Draw-TrophyCup $gr ($ix + 13) ($iy + 12) 32 $c
            }
        }
        $rw = 200
        $tx = $ix + 74; $tw = $r.Right - $tx - $rw - 12
        $name = $t.name; $det = $t.detail
        if ($secret) { $name = 'Troféu oculto'; $det = 'Continue jogando para descobrir.' }
        $nc = $fg; if (-not $t.earned) { $nc = [System.Drawing.Color]::FromArgb(205, 205, 215) }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($name)), $fontBold, (New-Object System.Drawing.Rectangle($tx, ($r.Y + 13), $tw, 24)), $nc, $TrTextFlags)
        $df = [System.Windows.Forms.TextFormatFlags]'EndEllipsis, NoPrefix, WordBreak'
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($det)), $fontTrSmall, (New-Object System.Drawing.Rectangle($tx, ($r.Y + 38), $tw, 34)), $dim, $df)
        # coluna da direita: tipo do troféu e data (ou raridade)
        $rx = $r.Right - $rw - 10
        $c = $TrophyColors[$t.grade]; if (-not $t.earned) { $c = [System.Drawing.Color]::FromArgb(120, $c) }
        Draw-TrophyCup $gr $rx ($r.Y + 15) 18 $c
        $gl = $TrophyNames[$t.grade]; if ($t.points) { $gl += "  ·  $($t.points) pts" }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($gl)), $fontTrSmall, (New-Object System.Drawing.Rectangle(($rx + 24), ($r.Y + 13), ($rw - 24), 22)), $fg, $TrTextFlags)
        if ($t.earned) {
            $st = 'Conquistado'; if ($t.time) { $st = "Conquistado em $($t.time.ToString('dd/MM/yyyy'))" }
            $sc = $okColor
        } else { $st = 'Não conquistado'; $sc = $dim }
        [System.Windows.Forms.TextRenderer]::DrawText($gr, (L ($st)), $fontTrSmall, (New-Object System.Drawing.Rectangle($rx, ($r.Y + 37), $rw, 18)), $sc, $TrTextFlags)
        if ($null -ne $t.rarity) {
            [System.Windows.Forms.TextRenderer]::DrawText($gr, (L (('{0:N1}% dos jogadores têm' -f $t.rarity))), $fontTrSmall, (New-Object System.Drawing.Rectangle($rx, ($r.Y + 55), $rw, 18)), $dim, $TrTextFlags)
        }
    })
# a lista não usa seleção: só rola
$trList.Add_SelectedIndexChanged({ if ($this.SelectedIndex -ge 0) { $this.ClearSelected() } })

$trRight.Controls.Add($trList)
$trRight.Controls.Add($trGameHead)
$trBody.Controls.Add($trRight)
$trBody.Controls.Add($trGap)
$trBody.Controls.Add($trGames)

# sem troféus ainda: explica de onde eles vêm
$trEmpty = New-Object System.Windows.Forms.Label
$trEmpty.Dock = 'Fill'; $trEmpty.TextAlign = 'MiddleCenter'; $trEmpty.ForeColor = $dim; $trEmpty.Font = New-Object System.Drawing.Font('Segoe UI', 11)
$trEmpty.Text = "Nenhum troféu ainda`n`n" +
"PS2: entre na sua conta RetroAchievements em ""Contas e opções"" e jogue.`n" +
"PS3: os troféus do RPCS3 aparecem aqui sozinhos depois que você joga.`n" +
"PS4: o shadPS4 precisa da chave de troféus do seu próprio PS4."
$trEmpty.Visible = $false

$trophyView.Controls.Add($trBody)
$trophyView.Controls.Add($trEmpty)
$trophyView.Controls.Add($trHead)

function Update-TrophyData {
    $sets = @(Get-Ps2TrophySets) + @(Get-Ps3TrophySets) + @(Get-Ps4TrophySets) + @(Get-Ps4GameTrophySets)
    # um cartão por jogo: quem já tem troféus reais recebe as conquistas Trivium no mesmo cartão
    foreach ($tr in @(Get-TriviumTrophySets)) {
        $same = $sets | Where-Object { $_.platform -eq $tr.platform -and ($_.title -replace '[®™]', '').Trim() -ieq ($tr.title -replace '[®™]', '').Trim() } | Select-Object -First 1
        if (-not $same) { $sets += $tr; continue }
        foreach ($t in $tr.trophies) { [void]$same.trophies.Add($t) }
        if ($tr.last -gt $same.last) { $same.last = $tr.last }
    }
    foreach ($s in $sets) { Update-TrophyStats $s }
    try { Start-Ps4TextRefresh } catch { Write-AppLog "Nomes de troféus: $($_.Exception.Message)" }
    # jogo com troféu mais recente primeiro, como no PS5
    $script:TrophySets = @($sets | Where-Object { $_.total -gt 0 } |
            Sort-Object @{ Expression = { $_.last }; Descending = $true }, @{ Expression = { $_.earned }; Descending = $true }, @{ Expression = { $_.title } })
}

function Update-TrophyStatus {
    $acc = Get-RaAccount
    if ($script:RaJob) { $trStatus.Text = 'Atualizando conquistas do PS2...' }
    elseif (-not $acc) { $trStatus.Text = 'PS2: entre na sua conta RetroAchievements em "Contas e opções"' }
    elseif ($script:RaError) { $trStatus.Text = "PS2: não deu para atualizar ($($script:RaError))" }
    elseif ($script:RaLastFetch) { $trStatus.Text = "PS2: conta $($acc.user), atualizado às $($script:RaLastFetch.ToString('HH:mm'))" }
    else { $trStatus.Text = "PS2: conta $($acc.user)" }
}

function Update-TrophyGames {
    $keep = $null; if ($trGames.SelectedItem) { $keep = $trGames.SelectedItem.key }
    $f = $txtSearch.Text.Trim()
    $trGames.BeginUpdate()
    $trGames.Items.Clear()
    $idx = 0
    foreach ($s in $script:TrophySets) {
        if ($f -and $s.title -notlike "*$f*") { continue }
        if ($keep -and $s.key -eq $keep) { $idx = $trGames.Items.Count }
        [void]$trGames.Items.Add($s)
    }
    $trGames.EndUpdate()
    if ($trGames.Items.Count) { $trGames.SelectedIndex = $idx } else { Update-TrophyList }
    $has = $script:TrophySets.Count -gt 0
    $trBody.Visible = $has; $trEmpty.Visible = -not $has
    Update-TrophyStatus
    $trHead.Invalidate()
}

function Update-TrophyList {
    $set = $trGames.SelectedItem
    $trList.BeginUpdate()
    $trList.Items.Clear()
    $n = @{ todos = 0; ganhos = 0; faltam = 0 }
    if ($set) {
        foreach ($t in $set.trophies) {
            $n.todos++; if ($t.earned) { $n.ganhos++ } else { $n.faltam++ }
            if ($script:TrFilter -eq 'ganhos' -and -not $t.earned) { continue }
            if ($script:TrFilter -eq 'faltam' -and $t.earned) { continue }
            [void]$trList.Items.Add($t)
        }
    }
    $trList.EndUpdate()
    if ($trList.Items.Count) { $trList.TopIndex = 0 }
    $labels = @{ todos = 'Todos'; ganhos = 'Conquistados'; faltam = 'Não conquistados' }
    foreach ($fk in $script:TrFilterButtons.Keys) {
        $fb = $script:TrFilterButtons[$fk]
        $fb.Text = "$($labels[$fk])  $($n[$fk])"
        $fb.Width = [System.Windows.Forms.TextRenderer]::MeasureText($fb.Text, $fb.Font).Width + 28
        if ($fk -eq $script:TrFilter) { $fb.BackColor = $accent; $fb.ForeColor = $fg; $fb.FlatAppearance.BorderSize = 0 }
        else { $fb.BackColor = $panelBg; $fb.ForeColor = $dim; $fb.FlatAppearance.BorderSize = 1 }
    }
    # a barra enche de novo só ao trocar de jogo, não a cada atualização da lista
    if ($set -and $set.key -ne $script:TrBarKey) { $script:TrBarKey = $set.key; $script:TrBar = 0.0; $animTimer.Start() }
    $trGameHead.Invalidate()
}

function Start-RaRefresh([bool]$force = $false) {
    if ($script:RaJob) { return }
    $acc = Get-RaAccount
    if (-not $acc) { return }
    # não pergunta ao site toda vez que a aba abre (a não ser que um jogo de PS2 tenha acabado de fechar)
    if (-not $force -and $script:RaLastFetch -and ((Get-Date) - $script:RaLastFetch).TotalMinutes -lt 3) { return }
    $extra = [int[]]@($script:Cfg.games | Where-Object { $_.raGameId } | ForEach-Object { [int]$_.raGameId })
    New-Item -ItemType Directory -Force $TrophyDir | Out-Null
    $ps = [powershell]::Create()
    [void]$ps.AddScript($RaFetchScript).AddArgument($acc.user).AddArgument($acc.token).AddArgument($extra).AddArgument($TrophyDir)
    $script:RaError = ''
    $script:RaJob = @{ ps = $ps; handle = $ps.BeginInvoke() }
    $raTimer.Start()
    Update-TrophyStatus
}

$raTimer = New-Object System.Windows.Forms.Timer
$raTimer.Interval = 400
$raTimer.Add_Tick({
        $j = $script:RaJob
        if (-not $j) { $raTimer.Stop(); return }
        if (-not $j.handle.IsCompleted) { return }
        $raTimer.Stop()
        $script:RaJob = $null
        try {
            $res = @($j.ps.EndInvoke($j.handle))
            Save-RaCache $res
            $script:RaLastFetch = Get-Date
        } catch {
            $msg = $_.Exception.InnerException; if (-not $msg) { $msg = $_.Exception }
            $script:RaError = ($msg.Message -split "`n")[0]
            if ($script:RaError -match '(?i)remote name|conectar|connect') { $script:RaError = 'sem internet' }
        }
        $j.ps.Dispose()
        $script:TrImg.Clear()
        if ($script:TrophyMode) { Update-TrophyData; Update-TrophyGames } else { Update-TrophyStatus }
    })

$trBtnRef.Add_Click({ Update-TrophyData; Update-TrophyGames; Start-RaRefresh $true })
$trBtnAcc.Add_Click({ Show-AchievementsDialog; $script:RaLastFetch = $null; Update-TrophyData; Update-TrophyGames; Start-RaRefresh $true })

function Show-TrophyView {
    Invoke-UiFrozen {
        if (-not $script:TrophyMode) {
            $script:TrophyMode = $true
            $libPanel.Visible = $false; $detail.Visible = $false; $btnSort.Visible = $false
            $trophyView.Visible = $true
            Update-ConsoleTabs
        }
        Update-TrophyData
        Update-TrophyGames
        Start-RaRefresh
        [void]$trGames.Focus()
    }
}

function Hide-TrophyView {
    if (-not $script:TrophyMode) { return }
    $script:TrophyMode = $false
    $trophyView.Visible = $false; $libPanel.Visible = $true; $btnSort.Visible = $true
}

# ---- sons da interface (modo TV): gerados na hora, sem arquivos de som; liga/desliga com S ou no alto-falante
function New-ToneWav([double[]]$freqs, [int]$ms, [double]$vol = 0.18) {
    # WAV 16 bits mono 44,1 kHz: cada frequência é um toque curto com ataque e queda suaves
    $rate = 44100; $per = [int]($rate * $ms / 1000); $n = $per * $freqs.Count
    $ms2 = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($ms2)
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n * 2)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]($n * 2))
    foreach ($f in $freqs) {
        for ($i = 0; $i -lt $per; $i++) {
            $env = [math]::Min(1.0, $i / ($rate * 0.004)) * [math]::Pow(1 - $i / $per, 2)
            $w.Write([int16](32767 * $vol * $env * [math]::Sin(2 * [math]::PI * $f * $i / $rate)))
        }
    }
    $w.Flush(); $ms2.Position = 0
    $sp = New-Object System.Media.SoundPlayer($ms2); $sp.Load()
    return $sp
}
$UiSounds = @{}
function Switch-UiSounds {
    $script:Cfg.uiSounds = ($script:Cfg.uiSounds -eq $false)
    Save-Config
    Play-UiSound 'tab'
    if ($script:TvForm) { $script:TvForm.Invalidate() }
}

function Play-UiSound([string]$name) {
    if ($script:Cfg.uiSounds -eq $false) { return }
    try {
        if (-not $UiSounds.Count) {
            $UiSounds.move = New-ToneWav @(1320) 28 0.10
            $UiSounds.tab = New-ToneWav @(990) 34 0.12
            $UiSounds.ok = New-ToneWav @(880, 1320) 55 0.16
            $UiSounds.back = New-ToneWav @(660, 440) 50 0.14
        }
        $UiSounds[$name].Play()
    } catch {}
}

# ---- modo TV: tela cheia para jogar no sofá com controle (fileira de capas grandes, como a tela inicial de um console)
$script:TvForm = $null
$script:Tv = @{ games = @(); index = 0; offset = 0.0; filter = 'Todos'; imgs = @{}; backs = @{}; tiles = @{}; hit = @() }
$fontTvGlyph = New-Object System.Drawing.Font('Segoe MDL2 Assets', 16)
$fontTvStar = New-Object System.Drawing.Font('Segoe MDL2 Assets', 18)
$TvClock = [Diagnostics.Stopwatch]::StartNew()
$tvShadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 0, 0, 0))
$tvFavBrush = New-Object System.Drawing.SolidBrush($FavColor)
$TvFilters = @('Todos', 'Favoritos', 'PS2', 'PS3', 'PS4')
$fontTvTitle = New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Bold)
$fontTvInfo = New-Object System.Drawing.Font('Segoe UI', 14)
$fontTvTab = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$fontTvHint = New-Object System.Drawing.Font('Segoe UI', 12)
$fontTvBtn = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)

function Get-TvCover($g) {
    # capa no tamanho original (a da grade é pequena demais para a TV)
    $key = Get-CoverImageKey $g
    if ($script:Tv.imgs.ContainsKey($key)) { return $script:Tv.imgs[$key] }
    $img = $null
    $file = Join-Path $CoverDir "$key.png"
    if ($g.cover) { $file = Join-Path $CoverDir $g.cover }
    if (-not $key.StartsWith('ph_') -and (Test-Path -LiteralPath $file)) {
        try { $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($file)); $img = [System.Drawing.Image]::FromStream($ms) } catch {}
    }
    if (-not $img) { $img = Get-DetailCover $g }
    $script:Tv.imgs[$key] = $img
    return $img
}

function Get-TvTile($g, [int]$w, [int]$h, [bool]$sel) {
    # capa já pronta no tamanho exato, com cantos arredondados (e escurecida se não for a escolhida):
    # durante o deslize só copia a imagem, sem redimensionar nem recortar a cada quadro
    $key = "$(Get-CoverImageKey $g)|$w|$h|$sel"
    if ($script:Tv.tiles.ContainsKey($key)) { return $script:Tv.tiles[$key] }
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $tg = [System.Drawing.Graphics]::FromImage($bmp)
    $tg.SmoothingMode = 'AntiAlias'; $tg.InterpolationMode = 'HighQualityBicubic'; $tg.PixelOffsetMode = 'HighQuality'
    $path = New-RoundRect 0 0 ($w - 1) ($h - 1) 14
    $tg.SetClip($path)
    $tg.DrawImage((Get-TvCover $g), 0, 0, $w, $h)
    if (-not $sel) { $tg.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 0, 0, 0))), 0, 0, $w, $h) }
    $tg.ResetClip()
    if ($sel) { $tg.DrawPath((New-Object System.Drawing.Pen([System.Drawing.Color]::White, 4)), (New-RoundRect 2 2 ($w - 5) ($h - 5) 13)) }
    $tg.Dispose()
    if ($script:Tv.tiles.Count -gt 80) { foreach ($v in $script:Tv.tiles.Values) { $v.Dispose() }; $script:Tv.tiles.Clear() }
    $script:Tv.tiles[$key] = $bmp
    return $bmp
}

function Get-TvBackdrop($g, [int]$w, [int]$h) {
    # fundo: a arte do próprio jogo, nítida (PS4: sce_sys\pic1.png; PS3: PIC1.PNG), como na tela inicial do PS5;
    # sem arte (PS2): a capa bem desfocada
    $key = "$($g.path)|$(Get-CoverImageKey $g)|$w|$h"
    if ($script:Tv.backs.ContainsKey($key)) { return $script:Tv.backs[$key] }
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $bg2 = [System.Drawing.Graphics]::FromImage($bmp)
    $art = $null
    $artFile = Get-GameArtFile $g
    if ($artFile) { try { $ms = New-Object IO.MemoryStream(, [IO.File]::ReadAllBytes($artFile)); $art = [System.Drawing.Image]::FromStream($ms) } catch {} }
    if ($art) {
        $bg2.InterpolationMode = 'HighQualityBicubic'; $bg2.PixelOffsetMode = 'HighQuality'
        $sc = [math]::Max($w / $art.Width, $h / $art.Height)
        $dw = [int]($art.Width * $sc); $dh = [int]($art.Height * $sc)
        $bg2.DrawImage($art, [int](($w - $dw) / 2), [int](($h - $dh) / 3), $dw, $dh)
        $art.Dispose()
        # escurece mais à esquerda, onde ficam as capas e o nome (a arte aparece bem à direita)
        $lgx = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(-2, 0, ($w + 4), $h)),
            [System.Drawing.Color]::FromArgb(170, 10, 10, 14), [System.Drawing.Color]::FromArgb(40, 10, 10, 14), 0)
        $bg2.FillRectangle($lgx, 0, 0, $w, $h)
    } else {
        $cover = Get-TvCover $g
        $tiny = New-Object System.Drawing.Bitmap(16, 12)
        $tg = [System.Drawing.Graphics]::FromImage($tiny); $tg.InterpolationMode = 'HighQualityBilinear'
        $tg.DrawImage($cover, 0, -6, 16, 22); $tg.Dispose()
        $bg2.InterpolationMode = 'HighQualityBilinear'
        $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetWrapMode('TileFlipXY')
        $bg2.DrawImage($tiny, (New-Object System.Drawing.Rectangle(-40, -40, ($w + 80), ($h + 80))), 0, 0, 16, 12, 'Pixel', $ia)
        $tiny.Dispose()
        $bg2.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 10, 10, 14))), 0, 0, $w, $h)
    }
    $gy = [int]($h * 0.45); $gh = [int]($h * 0.55) + 1
    # (o degradê começa 2 px antes da área pintada: sem isso o GDI+ desenha uma linha na borda)
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, ($gy - 2), $w, ($gh + 4))),
        [System.Drawing.Color]::FromArgb(0, 10, 10, 14), [System.Drawing.Color]::FromArgb(235, 10, 10, 14), 90)
    $bg2.FillRectangle($lg, 0, $gy, $w, $gh)
    $bg2.Dispose()
    if ($script:Tv.backs.Count -gt 12) { foreach ($v in $script:Tv.backs.Values) { $v.Dispose() }; $script:Tv.backs.Clear() }
    $script:Tv.backs[$key] = $bmp
    return $bmp
}

function Update-TvGames {
    $keep = $null; if ($script:Tv.games.Count) { $keep = $script:Tv.games[$script:Tv.index].path }
    $script:Tv.games = @(Get-SortedGames | Where-Object { Test-InTab $_ $script:Tv.filter })
    $script:Tv.index = 0
    for ($i = 0; $i -lt $script:Tv.games.Count; $i++) { if ($script:Tv.games[$i].path -eq $keep) { $script:Tv.index = $i } }
    $script:Tv.offset = [double]$script:Tv.index
}

function Step-TvSelection([int]$step) {
    $n = $script:Tv.games.Count
    if ($n -eq 0) { return }
    $old = $script:Tv.index
    $script:Tv.index = [math]::Max(0, [math]::Min($n - 1, $script:Tv.index + $step))
    if ($script:Tv.index -ne $old) { Play-UiSound 'move' }
    Start-TvAnim
    $script:TvForm.Invalidate()
}

function Step-TvFilter([int]$step) {
    $i = [array]::IndexOf($TvFilters, $script:Tv.filter) + $step
    if ($i -lt 0) { $i = $TvFilters.Count - 1 } elseif ($i -ge $TvFilters.Count) { $i = 0 }
    $script:Tv.filter = $TvFilters[$i]
    Play-UiSound 'tab'
    Update-TvGames
    $script:TvForm.Invalidate()
}

function Get-TvSelected {
    if ($script:Tv.games.Count -eq 0) { return $null }
    return $script:Tv.games[$script:Tv.index]
}

function Start-TvGame {
    $g = Get-TvSelected
    if (-not $g) { return }
    if ($script:RunDir) { return }
    Play-UiSound 'ok'
    [void](Select-Game $g)
    # no modo TV não para na tela de configurações: abre direto (Y/Triângulo configura)
    Start-Game $g
    $script:TvForm.Invalidate()
}

function Open-TvSettings {
    $g = Get-TvSelected
    if (-not $g) { return }
    if ($script:TvStageOk) { $tvSync.Stop(); [PL.TvStage]::Stop() }
    $script:TvForm.Hide()
    [void](Show-GameSettings $g $false)
    $script:TvForm.Show(); $script:TvForm.Activate()
    if ($script:TvStageOk) { Sync-TvStage; $tvSync.Start() }
}

function Switch-TvFavorite {
    $g = Get-TvSelected
    if (-not $g) { return }
    if ($g.favorite) { $g.PSObject.Properties.Remove('favorite') } else { $g | Add-Member -NotePropertyName favorite -NotePropertyValue $true -Force }
    Save-Config
    if ($script:Tv.filter -eq 'Favoritos') { Update-TvGames }
    $script:TvForm.Invalidate()
}

function Close-TvMode {
    if (-not $script:TvForm) { return }
    Play-UiSound 'back'
    $tvAnim.Stop()
    if ($script:TvStageOk) { $tvSync.Stop(); [PL.TvStage]::Stop() }
    $script:TvForm.Hide()
    Refresh-List
    $g = Get-TvSelected; if ($g) { [void](Select-Game $g) }
    $form.Activate()
}

# enquanto o modo TV está na tela e nenhum jogo roda, a cena fica viva (partículas, brilho da capa);
# ritmo alto só durante as transições, para não gastar processador à toa
$script:TvFx = @{ sel = $null; cur = $null; old = $null; change = -9.0; enter = -9.0; tabX = -1.0; tabW = 0.0; settled = $true }
$script:TvDots = @(1..30 | ForEach-Object { @{ x = (Get-Random -Maximum 1000) / 1000.0; y = (Get-Random -Maximum 1000) / 1000.0; s = 2 + (Get-Random -Maximum 4); v = 0.012 + (Get-Random -Maximum 30) / 1000.0; p = (Get-Random -Maximum 628) / 100.0 } })
$tvDotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, 255, 255, 255))
$tvAnim = New-Object System.Windows.Forms.Timer
$tvAnim.Interval = 16
$tvAnim.Add_Tick({
        if (-not $script:TvForm -or -not $script:TvForm.Visible -or $script:RunDir) { $tvAnim.Stop(); return }
        # desliza a fileira até a capa escolhida, desacelerando no fim; pelo tempo que passou
        # (não pelo número de quadros), então a velocidade é a mesma mesmo se um quadro atrasar
        $now = $TvClock.Elapsed.TotalSeconds
        $dt = [math]::Min(0.05, $now - $script:Tv.last); $script:Tv.last = $now
        $d = $script:Tv.index - $script:Tv.offset
        $moving = [math]::Abs($d) -ge 0.003
        if ($moving) { $script:Tv.offset += $d * (1 - [math]::Exp(-$dt * 13)); $script:TvFx.settled = $false }
        else { $script:Tv.offset = [double]$script:Tv.index }
        $fast = $moving -or ($now - $script:TvFx.change) -lt 0.6 -or ($now - $script:TvFx.enter) -lt 0.7
        $iv = 66; if ($fast) { $iv = 16 }
        if ($tvAnim.Interval -ne $iv) { $tvAnim.Interval = $iv }
        $script:TvForm.Invalidate()
        $script:TvForm.Update()
        if (-not $moving -and -not $script:TvFx.settled) { $script:TvFx.settled = $true; Initialize-TvNeighbors }
    })

function Initialize-TvNeighbors {
    # parado: já prepara o fundo e as capas dos jogos ao lado, para o próximo deslize não engasgar
    $f = $script:TvForm
    if (-not $f -or -not $f.Visible) { return }
    $W = $f.ClientSize.Width; $H = $f.ClientSize.Height
    $ch = [int]($H * 0.36); $cw = [int]($ch * 0.75)
    foreach ($i in ($script:Tv.index - 1), ($script:Tv.index + 1)) {
        if ($i -lt 0 -or $i -ge $script:Tv.games.Count) { continue }
        $g = $script:Tv.games[$i]
        [void](Get-TvBackdrop $g $W $H)
        [void](Get-TvTile $g ([int]($cw * 1.16)) ([int]($ch * 1.16)) $true)
        [void](Get-TvTile $g $cw $ch $false)
    }
}

function Start-TvAnim {
    if ($script:TvStageOk) { Sync-TvStage; return }
    if (-not $tvAnim.Enabled) { $script:Tv.last = $TvClock.Elapsed.TotalSeconds - 0.016 }
    $tvAnim.Start()
}

function New-TvLayer([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $lg = [System.Drawing.Graphics]::FromImage($bmp)
    $lg.SmoothingMode = 'AntiAlias'; $lg.TextRenderingHint = 'AntiAliasGridFit'
    return @{ bmp = $bmp; gr = $lg }
}

function Sync-TvStage {
    # só refaz o que mudou; cada quadro é desenhado por PL.TvStage com estas imagens prontas
    $f = $script:TvForm
    if (-not $f -or -not $f.Visible) { return }
    $W = $f.ClientSize.Width; $H = $f.ClientSize.Height
    if ($W -lt 100 -or $H -lt 100) { return }
    $games = @($script:Tv.games); $sel = Get-TvSelected
    $m = [int]($W * 0.06)
    $ch = [int]($H * 0.36); $cw = [int]($ch * 0.75); $gap = [int]($cw * 0.14); $rowY = [int]($H * 0.17)
    $infoY = $rowY + [int]($ch * 1.28)
    $footH = 90
    [PL.TvStage]::SetLayout($m, $cw, $ch, $gap, $rowY, $infoY, ($H - $footH))
    $dimB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(185, 185, 200))
    $white = [System.Drawing.Brushes]::White
    $clock = (Get-Date).ToString('HH:mm')
    $chromeKey = "$W|$H|$($script:Tv.filter)|$clock|$($script:Cfg.uiSounds)"
    if ($chromeKey -ne $script:TvChromeKey) {
        $script:TvChromeKey = $chromeKey
        $t = New-TvLayer $W 90; $gr = $t.gr
        $hits = @()
        $gr.DrawString((L ('TRIVIUM HUB')), $fontTvTab, $dimB, $m, 34)
        $tx = [int]($W * 0.30)
        foreach ($name in $TvFilters) {
            $sz = $gr.MeasureString($name, $fontTvTab)
            $on = $name -eq $script:Tv.filter
            $b = $dimB; if ($on) { $b = $white }
            $gr.DrawString((L ($name)), $fontTvTab, $b, $tx, 34)
            if ($on) {
                $c = $accent; if ($consoleColors.ContainsKey($name)) { $c = $consoleColors[$name] }; if ($name -eq 'Favoritos') { $c = $FavColor }
                [PL.TvStage]::SetTab(($tx + 2), ($sz.Width - 8), $c.ToArgb())
            }
            $hits += @{ kind = 'tab'; tab = $name; rect = (New-Object System.Drawing.Rectangle($tx, 28, [int]$sz.Width, 44)) }
            $tx += [int]$sz.Width + 34
        }
        $cs = $gr.MeasureString($clock, $fontTvTab)
        $gr.DrawString((L ($clock)), $fontTvTab, $white, $W - $m - $cs.Width, 34)
        $sx = [int]($W - $m - $cs.Width - 52)
        $sg = 0xE767; if ($script:Cfg.uiSounds -eq $false) { $sg = 0xE74F }
        $gr.DrawString([string][char]$sg, $fontTvGlyph, $dimB, $sx, 36)
        $hits += @{ kind = 'sound'; rect = (New-Object System.Drawing.Rectangle($sx, 28, 40, 40)) }
        $gr.Dispose()
        $b2 = New-TvLayer $W $footH; $gr = $b2.gr
        $hint = 'Ⓐ / ✕  Jogar        Ⓨ / △  Configurar        Ⓧ / ▢  Favorito        LB / RB  Console        Ⓑ / ○  Sair do modo TV'
        $gr.DrawString((L ($hint)), $fontTvHint, $dimB, $m, 26)
        $ex = 'Sair  (Esc)'; $es = $gr.MeasureString($ex, $fontTvHint)
        $gr.DrawString((L ($ex)), $fontTvHint, $white, $W - $m - $es.Width, 26)
        $hits += @{ kind = 'exit'; rect = (New-Object System.Drawing.Rectangle([int]($W - $m - $es.Width), ($H - 70), [int]$es.Width, 36)) }
        $gr.Dispose()
        $was = $script:TvChromeOld
        [PL.TvStage]::SetChrome($t.bmp, $b2.bmp)
        $script:TvChromeOld = @($t.bmp, $b2.bmp)
        if ($was) { foreach ($o in $was) { $o.Dispose() } }
        $script:Tv.chromeHits = $hits
    }
    $playing = [bool]$script:RunDir
    $infoKey = "$W|$($sel.path)|$playing|$($script:Tv.index)|$($games.Count)|$($sel.playSeconds)"
    if ($infoKey -ne $script:TvInfoKey) {
        $script:TvInfoKey = $infoKey
        $n = New-TvLayer ([int]($W * 0.8)) 200; $gr = $n.gr
        $playHit = $null
        if (-not $sel) {
            $sf0 = New-Object System.Drawing.StringFormat; $sf0.Alignment = 'Center'
            $gr.DrawString((L ('Nenhum jogo aqui')), $fontTvTitle, $white, (New-RectF 0 0 ($W * 0.8) 60), $sf0)
        } else {
            $gr.DrawString((L ($sel.name)), $fontTvTitle, $white, (New-RectF $m 0 ($W * 0.8 - $m) 60))
            $kind = Get-ConsoleKind $sel
            $cc = $accent; if ($consoleColors.ContainsKey($kind)) { $cc = $consoleColors[$kind] }
            $kw = $gr.MeasureString($kind, $fontTvTab).Width + 22
            $gr.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, $cc))), (New-RoundRect $m 66 $kw 32 8))
            $gr.DrawString((L ($kind)), $fontTvTab, (New-Object System.Drawing.SolidBrush($cc)), $m + 11, 69)
            $info = "Tempo jogado: $(Format-PlayTime ([int]$sel.playSeconds))     Última vez: $(Format-LastPlayed $sel.lastPlayed)"
            if (-not $sel.playSeconds) { $info = 'Ainda não jogado' }
            $gr.DrawString((L ($info)), $fontTvInfo, $dimB, $m + $kw + 18, 68)
            $bt = 'JOGAR'; if ($playing) { $bt = 'JOGO ABERTO' }
            $bw = 220; $by = 124
            $gr.FillPath((New-Object System.Drawing.SolidBrush($(if ($playing) { [System.Drawing.Color]::FromArgb(70, 70, 84) } else { $accent }))), (New-RoundRect $m $by $bw 58 12))
            $sfc = New-Object System.Drawing.StringFormat; $sfc.Alignment = 'Center'; $sfc.LineAlignment = 'Center'
            $gr.DrawString((L ($bt)), $fontTvBtn, $white, (New-RectF $m $by $bw 58), $sfc)
            $gr.DrawString((L ("$($script:Tv.index + 1) de $($games.Count)")), $fontTvHint, $dimB, $m + $bw + 24, $by + 17)
            $playHit = @{ kind = 'play'; rect = (New-Object System.Drawing.Rectangle($m, ($infoY + $by), $bw, 58)) }
        }
        $gr.Dispose()
        $was = $script:TvInfoOld
        [PL.TvStage]::SetInfo($n.bmp)
        $script:TvInfoOld = $n.bmp
        if ($was) { $was.Dispose() }
        $script:Tv.playHit = $playHit
    }
    $script:Tv.hit = @($script:Tv.chromeHits) + @($script:Tv.playHit | Where-Object { $_ })
    if ($sel) { [PL.TvStage]::SetBack((Get-TvBackdrop $sel $W $H)) }
    # capas perto da escolhida; as demais entram conforme a fileira anda
    $tileKey = "$W|$($script:Tv.index)|$($games.Count)|$($script:Tv.filter)|" + (@($games | Where-Object { $_.favorite } | ForEach-Object { $_.path }) -join ',')
    if ($tileKey -ne $script:TvTileKey) {
        $script:TvTileKey = $tileKey
        $bigW = [int]($cw * 1.16); $bigH = [int]($ch * 1.16)
        $span = [int]($W / ($cw + $gap)) + 3
        [PL.TvStage]::BeginTiles($games.Count)
        for ($i = [math]::Max(0, $script:Tv.index - 2); $i -lt [math]::Min($games.Count, $script:Tv.index + $span); $i++) {
            $g = $games[$i]
            [PL.TvStage]::SetTile($i, (Get-TvTile $g $cw $ch $false), (Get-TvTile $g $bigW $bigH $false), (Get-TvTile $g $bigW $bigH $true), [bool]$g.favorite)
        }
    }
    [PL.TvStage]::SetIndex($script:Tv.index, $false)
    if ($script:RunDir) { [PL.TvStage]::Stop() } else { [PL.TvStage]::Start($false) }
}

# pega as mudanças que não passam por Start-TvAnim (aba, favorito, relógio, jogo abrindo e fechando)
$tvSync = New-Object System.Windows.Forms.Timer
$tvSync.Interval = 120
$tvSync.Add_Tick({
        if (-not $script:TvForm -or -not $script:TvForm.Visible) { $tvSync.Stop(); return }
        try {
            Sync-TvStage
            if ([PL.TvStage]::TakeSettled()) { Initialize-TvNeighbors }
            # diagnóstico: quadros desenhados e tempo de cada um, só quando pedido por esta variável de ambiente
            if ($env:TRIVIUM_TV_STATS) { [IO.File]::WriteAllText($env:TRIVIUM_TV_STATS, "$([PL.TvStage]::Frames) $([PL.TvStage]::DrawMs) $([PL.TvStage]::LastError)") }
        } catch { Write-AppLog "Modo TV: $($_.Exception.Message)" }
    })

function Show-TvMode {
    if (-not $script:TvForm) {
        $f = New-Object System.Windows.Forms.Form
        $f.Text = 'Trivium Hub - Modo TV'; $f.FormBorderStyle = 'None'; $f.WindowState = 'Maximized'
        $f.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14); $f.KeyPreview = $true; $f.ShowInTaskbar = $true
        if ($form.Icon) { $f.Icon = $form.Icon }
        [System.Windows.Forms.Form].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic, Instance').SetValue($f, $true, $null)
        if ($script:TvStageOk) { [PL.TvStage]::Attach($f, $fontTvStar, $tvFavBrush) }
        else { $f.Add_Paint({ Draw-TvMode $_.Graphics $this.ClientSize.Width $this.ClientSize.Height }) }
        $f.Add_Resize({ $this.Invalidate() })
        $f.Add_KeyDown({
                $k = $_
                switch ($k.KeyCode) {
                    'Left' { Step-TvSelection -1 } 'Right' { Step-TvSelection 1 }
                    'Return' { Start-TvGame } 'Enter' { Start-TvGame } 'Escape' { Close-TvMode } 'F11' { Close-TvMode }
                    'F2' { Open-TvSettings } 'Q' { Step-TvFilter -1 } 'E' { Step-TvFilter 1 } 'Tab' { Step-TvFilter 1 }
                    'F' { Switch-TvFavorite }
                    'S' { Switch-UiSounds }
                }
                $k.Handled = $true; $k.SuppressKeyPress = $true
            })
        $f.Add_MouseWheel({ if ($_.Delta -gt 0) { Step-TvSelection -1 } else { Step-TvSelection 1 } })
        $f.Add_MouseClick({
                $p = $_.Location
                if ($script:TvStageOk) {
                    $gi = [PL.TvStage]::HitGame($p.X, $p.Y)
                    if ($gi -ge 0) { if ($gi -eq $script:Tv.index) { Start-TvGame } else { $script:Tv.index = $gi; Start-TvAnim }; return }
                }
                foreach ($h in $script:Tv.hit) {
                    if (-not $h.rect.Contains($p)) { continue }
                    switch ($h.kind) {
                        'game' { if ($h.i -eq $script:Tv.index) { Start-TvGame } else { $script:Tv.index = $h.i; Start-TvAnim } }
                        'play' { Start-TvGame }
                        'tab' { $script:Tv.filter = $h.tab; Update-TvGames }
                        'exit' { Close-TvMode }
                        'sound' { Switch-UiSounds }
                    }
                    $this.Invalidate(); return
                }
            })
        # relógio do canto atualiza sozinho
        $clock = New-Object System.Windows.Forms.Timer; $clock.Interval = 20000
        $clock.Add_Tick({ if ($script:TvForm.Visible) { $script:TvForm.Invalidate() } }); $clock.Start()
        $script:TvForm = $f
    }
    $sel = Get-Selected
    $script:Tv.filter = 'Todos'
    Update-TvGames
    if ($sel) { for ($i = 0; $i -lt $script:Tv.games.Count; $i++) { if ($script:Tv.games[$i].path -eq $sel.path) { $script:Tv.index = $i; $script:Tv.offset = [double]$i } } }
    $script:TvFx.enter = $TvClock.Elapsed.TotalSeconds
    $script:TvForm.Show(); $script:TvForm.Activate(); $script:TvForm.Invalidate()
    if ($script:TvStageOk) {
        Sync-TvStage
        [PL.TvStage]::SetIndex($script:Tv.index, $true)
        [PL.TvStage]::Start($true)
        $tvSync.Start()
    } else { Start-TvAnim }
}

function Draw-TvMode($gr, [int]$W, [int]$H) {
    $fxNow = $TvClock.Elapsed.TotalSeconds
    $fx = $script:TvFx
    # imagens já vêm no tamanho certo: cópia simples (rápida), sem suavizar de novo a cada quadro
    $gr.SmoothingMode = 'AntiAlias'; $gr.InterpolationMode = 'NearestNeighbor'; $gr.PixelOffsetMode = 'Half'
    $gr.CompositingQuality = 'HighSpeed'; $gr.TextRenderingHint = 'AntiAliasGridFit'
    $script:Tv.hit = @()
    $games = $script:Tv.games
    $sel = Get-TvSelected
    if ($sel) {
        $backNew = Get-TvBackdrop $sel $W $H
        if ($fx.sel -ne $sel.path) { $fx.old = $fx.cur; $fx.cur = $backNew; $fx.sel = $sel.path; $fx.change = $fxNow }
        $fxP = [math]::Min(1.0, ($fxNow - $fx.change) / 0.42)
        if ($fx.old -and $fxP -lt 1) {
            # o fundo antigo vai dando lugar ao novo; uma imagem liberada do cache só cancela a transição
            try {
                $gr.DrawImageUnscaled($fx.old, 0, 0)
                $cm = New-Object System.Drawing.Imaging.ColorMatrix; $cm.Matrix33 = [single]$fxP
                $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
                $gr.DrawImage($backNew, (New-Object System.Drawing.Rectangle(0, 0, $W, $H)), 0, 0, $W, $H, 'Pixel', $ia); $ia.Dispose()
            } catch { $fx.old = $null; $gr.DrawImageUnscaled($backNew, 0, 0) }
        } else { $fx.old = $null; $gr.DrawImageUnscaled($backNew, 0, 0) }
    } else { $gr.Clear([System.Drawing.Color]::FromArgb(10, 10, 14)) }
    # partículas subindo devagar
    foreach ($dot in $script:TvDots) {
        $dy = 1 - (($dot.y + $fxNow * $dot.v) % 1)
        $dx = $dot.x + 0.01 * [math]::Sin($fxNow * 0.6 + $dot.p)
        $gr.FillEllipse($tvDotBrush, [single]($dx * $W), [single]($dy * $H), [single]$dot.s, [single]$dot.s)
    }
    $textIn = 1 - [math]::Pow(1 - [math]::Min(1.0, ($fxNow - $fx.change) / 0.4), 3)
    $enterIn = 1 - [math]::Pow(1 - [math]::Min(1.0, ($fxNow - $fx.enter) / 0.55), 3)
    $white = [System.Drawing.Brushes]::White
    $dimB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(185, 185, 200))
    $m = [int]($W * 0.06)
    # topo: marca, abas de console e relógio
    $gr.DrawString((L ('TRIVIUM HUB')), $fontTvTab, $dimB, $m, 34)
    $tx = [int]($W * 0.30)
    foreach ($t in $TvFilters) {
        $sz = $gr.MeasureString($t, $fontTvTab)
        $on = $t -eq $script:Tv.filter
        $b = $dimB; if ($on) { $b = $white }
        $gr.DrawString((L ($t)), $fontTvTab, $b, $tx, 34)
        if ($on) {
            $c = $accent; if ($consoleColors.ContainsKey($t)) { $c = $consoleColors[$t] }; if ($t -eq 'Favoritos') { $c = $FavColor }
            # a linha desliza até a aba escolhida
            if ($fx.tabX -lt 0) { $fx.tabX = $tx + 2.0; $fx.tabW = $sz.Width - 8.0 }
            $fx.tabX += ($tx + 2 - $fx.tabX) * 0.28; $fx.tabW += ($sz.Width - 8 - $fx.tabW) * 0.28
            $gr.FillRectangle((New-Object System.Drawing.SolidBrush($c)), [single]$fx.tabX, 66, [single]$fx.tabW, 3)
        }
        $script:Tv.hit += @{ kind = 'tab'; tab = $t; rect = (New-Object System.Drawing.Rectangle($tx, 28, [int]$sz.Width, 44)) }
        $tx += [int]$sz.Width + 34
    }
    $clock = (Get-Date).ToString('HH:mm')
    $cs = $gr.MeasureString($clock, $fontTvTab)
    $gr.DrawString((L ($clock)), $fontTvTab, $white, $W - $m - $cs.Width, 34)
    # alto-falante: liga/desliga os sons (tecla S)
    $sx = [int]($W - $m - $cs.Width - 52)
    $sg = 0xE767; if ($script:Cfg.uiSounds -eq $false) { $sg = 0xE74F }
    $gr.DrawString([string][char]$sg, $fontTvGlyph, $dimB, $sx, 36)
    $script:Tv.hit += @{ kind = 'sound'; rect = (New-Object System.Drawing.Rectangle($sx, 28, 40, 40)) }
    if ($games.Count -eq 0) {
        $sf0 = New-Object System.Drawing.StringFormat; $sf0.Alignment = 'Center'
        $gr.DrawString((L ('Nenhum jogo aqui')), $fontTvTitle, $white, (New-RectF 0 ($H * 0.4) $W 60), $sf0)
    } else {
        # fileira de capas: a escolhida fica à esquerda, maior e com contorno
        $ch = [int]($H * 0.36); $cw = [int]($ch * 0.75); $gap = [int]($cw * 0.14)
        $rowY = [int]($H * 0.17 + (1 - $enterIn) * 60)
        $first = [math]::Max(0, [int][math]::Floor($script:Tv.offset) - 1)
        $last = [math]::Min($games.Count - 1, $first + [int]($W / ($cw + $gap)) + 3)
        $bigW = [int]($cw * 1.16); $bigH = [int]($ch * 1.16)
        for ($i = $first; $i -le $last; $i++) {
            $near = [math]::Max(0.0, 1 - [math]::Abs($i - $script:Tv.offset))   # 1 na capa centrada, 0 a uma posição dela
            $x = $m + ($i - $script:Tv.offset) * ($cw + $gap)
            $x += $cw * 0.16 * [math]::Max(0.0, [math]::Min(1.0, $i - $script:Tv.offset))   # espaço para a capa escolhida (que é maior)
            $isSel = $i -eq $script:Tv.index
            $s = 1.0 + 0.16 * $near
            # (capW/capH: $w/$h apagariam $W/$H, o PowerShell não diferencia maiúsculas)
            $capW = [int]($cw * $s); $capH = [int]($ch * $s); $y = [int]($rowY - ($capH - $ch) / 2 + ($ch * 0.08))
            $x = [int]$x   # posição inteira: a capa pronta é só copiada, sem reamostrar
            if ($near -gt 0.5) { $gr.FillPath($tvShadow, (New-RoundRect ($x + 4) ($y + 10) $capW $capH 14)) }
            if ($near -gt 0.01) {
                $gr.InterpolationMode = 'Bilinear'
                $gr.DrawImage((Get-TvTile $games[$i] $bigW $bigH ($near -gt 0.5)), $x, $y, $capW, $capH)
                $gr.InterpolationMode = 'NearestNeighbor'
            } else { $gr.DrawImage((Get-TvTile $games[$i] $capW $capH $false), $x, $y, $capW, $capH) }
            if ($isSel -and $near -gt 0.9) {
                # brilho que respira em volta e reflexo que passa pela capa a cada 4 s
                $pulse = 0.5 + 0.5 * [math]::Sin($fxNow * 2.6)
                $ring = New-RoundRect ($x - 3) ($y - 3) ($capW + 6) ($capH + 6) 16
                $penG = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb((70 + [int](130 * $pulse)), 255, 255, 255), 2.5)
                $gr.DrawPath($penG, $ring); $penG.Dispose()
                $sw = ($fxNow % 4) / 0.9
                if ($sw -lt 1) {
                    $gr.SetClip((New-RoundRect $x $y $capW $capH 12))
                    $bx = [single]($x - $capW * 0.5 + $sw * $capW * 2)
                    $band = New-Object System.Drawing.RectangleF($bx, $y, ($capW * 0.5), $capH)
                    $lb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($band, [System.Drawing.Color]::Transparent, [System.Drawing.Color]::Transparent, [single]0)
                    $cb = New-Object System.Drawing.Drawing2D.ColorBlend
                    $cb.Colors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(60, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
                    $cb.Positions = [single[]]@(0, 0.5, 1)
                    $lb.InterpolationColors = $cb
                    $gr.FillRectangle($lb, $band); $lb.Dispose()
                    $gr.ResetClip()
                }
            }
            if ($games[$i].favorite) { $gr.DrawString([string][char]$Glyph.star, $fontTvStar, $tvFavBrush, [single]($x + $capW - 40), [single]($y + 10)) }
            $script:Tv.hit += @{ kind = 'game'; i = $i; rect = (New-Object System.Drawing.Rectangle([int]$x, [int]$y, [int]$capW, [int]$capH)) }
        }
        # informações do jogo escolhido
        # nome e dados sobem de leve ao trocar de jogo
        $iy = $rowY + [int]($ch * 1.28) + [int]((1 - $textIn) * 22)
        $titleB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](255 * $textIn), 255, 255, 255))
        $gr.DrawString((L ($sel.name)), $fontTvTitle, $titleB, (New-RectF $m $iy ($W - 2 * $m) 60)); $titleB.Dispose()
        $kind = Get-ConsoleKind $sel
        $cc = $accent; if ($consoleColors.ContainsKey($kind)) { $cc = $consoleColors[$kind] }
        $kw = $gr.MeasureString($kind, $fontTvTab).Width + 22
        $gr.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, $cc))), (New-RoundRect $m ($iy + 66) $kw 32 8))
        $gr.DrawString((L ($kind)), $fontTvTab, (New-Object System.Drawing.SolidBrush($cc)), $m + 11, $iy + 69)
        $info = "Tempo jogado: $(Format-PlayTime ([int]$sel.playSeconds))     Última vez: $(Format-LastPlayed $sel.lastPlayed)"
        if (-not $sel.playSeconds) { $info = 'Ainda não jogado' }
        $gr.DrawString((L ($info)), $fontTvInfo, $dimB, $m + $kw + 18, $iy + 68)
        # botão JOGAR
        $by = $iy + 124
        $playing = [bool]$script:RunDir
        $bt = 'JOGAR'; if ($playing) { $bt = 'JOGO ABERTO' }
        $bw = 220
        $gr.FillPath((New-Object System.Drawing.SolidBrush($(if ($playing) { [System.Drawing.Color]::FromArgb(70, 70, 84) } else { $accent }))), (New-RoundRect $m $by $bw 58 12))
        $sfc = New-Object System.Drawing.StringFormat; $sfc.Alignment = 'Center'; $sfc.LineAlignment = 'Center'
        $gr.DrawString((L ($bt)), $fontTvBtn, $white, (New-RectF $m $by $bw 58), $sfc)
        $script:Tv.hit += @{ kind = 'play'; rect = (New-Object System.Drawing.Rectangle($m, $by, $bw, 58)) }
        $gr.DrawString((L ("$($script:Tv.index + 1) de $($games.Count)")), $fontTvHint, $dimB, $m + $bw + 24, $by + 17)
    }
    # rodapé: comandos do controle e do teclado
    $hint = 'Ⓐ / ✕  Jogar        Ⓨ / △  Configurar        Ⓧ / ▢  Favorito        LB / RB  Console        Ⓑ / ○  Sair do modo TV'
    $gr.DrawString((L ($hint)), $fontTvHint, $dimB, $m, $H - 64)
    $ex = 'Sair  (Esc)'; $es = $gr.MeasureString($ex, $fontTvHint)
    $gr.DrawString((L ($ex)), $fontTvHint, $white, $W - $m - $es.Width, $H - 64)
    $script:Tv.hit += @{ kind = 'exit'; rect = (New-Object System.Drawing.Rectangle([int]($W - $m - $es.Width), ($H - 70), [int]$es.Width, 36)) }
    # entrada no modo TV: a tela surge do escuro
    if ($enterIn -lt 1) { $fadeIn = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](255 * (1 - $enterIn)), 8, 8, 12)); $gr.FillRectangle($fadeIn, 0, 0, $W, $H); $fadeIn.Dispose() }
}

# ---- dicas ao passar o mouse (escuras, como o resto do launcher), com o atalho de cada botão
$tips = New-Object System.Windows.Forms.ToolTip
$tips.OwnerDraw = $true; $tips.InitialDelay = 450; $tips.ReshowDelay = 150; $tips.AutoPopDelay = 8000
$fontTip = New-Object System.Drawing.Font('Segoe UI', 9.5)
$tips.Add_Popup({
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($this.GetToolTip($_.AssociatedControl), $fontTip)
        $_.ToolTipSize = New-Object System.Drawing.Size(($sz.Width + 20), ($sz.Height + 12))
    })
$tips.Add_Draw({
        $_.Graphics.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(44, 44, 54))), $_.Bounds)
        $_.Graphics.DrawRectangle((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(74, 74, 88))), 0, 0, $_.Bounds.Width - 1, $_.Bounds.Height - 1)
        [System.Windows.Forms.TextRenderer]::DrawText($_.Graphics, (L ($_.ToolTipText)), $fontTip, (New-Object System.Drawing.Point(10, 6)), $fg)
    })
$TipTexts = @(
    @($btnPlay, 'Jogar o jogo escolhido  (Enter / A no controle)'),
    @($btnSettings, 'Configurações deste jogo  (F2 / Y no controle)'),
    @($btnAddFile, 'Adicionar ISO, PKG ou EBOOT.BIN (ou arraste para a janela)'),
    @($btnAddDir, 'Adicionar uma pasta de jogo ou uma pasta com vários jogos'),
    @($btnRemove, 'Tirar da lista (o arquivo não é apagado)  (Delete)'),
    @($btnEmus, 'Instalar ou atualizar os emuladores, BIOS do PS2 e firmware do PS3'),
    @($btnAch, 'Troféus e conquistas de todos os jogos  (Ctrl+6)'),
    @($btnSort, 'Ordem dos jogos na biblioteca'),
    @($tabTrophy, 'Troféus e conquistas  (Ctrl+6)'),
    @($btnTv, 'Tela cheia para jogar no sofá com controle  (F11 / Back no controle)'),
    @($btnTvTop, 'Tela cheia para jogar no sofá com controle  (F11 / Back no controle)'),
    @($btnAdd, 'Adicionar ISO, PKG ou pastas de jogos (ou arraste para a janela)'),
    @($btnMore, 'Emuladores, conquistas, saves, primeiros passos e sobre'),
    @($btnAbout, 'Versão, créditos, licenças e diagnóstico'),
    @($btnSaves, 'Backup e restauração dos saves'),
    @($btnHelp, 'O que falta para jogar: emuladores, BIOS, firmware e jogos  (F1)'),
    @($btnSize, 'Tamanho das capas  (Ctrl + rodinha do mouse)'),
    @($btnView, 'Ver como grade de capas ou como lista')
)
foreach ($tt in $TipTexts) { $tips.SetToolTip($tt[0], (L $tt[1])) }
$tipN = 1
foreach ($n in $TabNames) { $tips.SetToolTip($script:TabButtons[$n], (L "Mostrar: $(L $n)  (Ctrl+$tipN)")); $tipN++ }

# ---- atalhos de teclado
$form.KeyPreview = $true
$form.Add_KeyDown({
        $k = $_
        if ($k.Control -and $k.KeyCode -eq 'F') { [void]$txtSearch.Focus(); $txtSearch.SelectAll(); $k.SuppressKeyPress = $true }
        elseif ($k.Control -and $k.KeyCode -eq 'D6') { Show-TrophyView; $k.SuppressKeyPress = $true }
        elseif ($k.Control -and $k.KeyCode -ge 'D1' -and $k.KeyCode -le 'D5') { Set-ConsoleFilter ($TabNames[[int]$k.KeyCode - [int][System.Windows.Forms.Keys]::D1]); $k.SuppressKeyPress = $true }
        elseif ($k.Control -and $k.KeyCode -eq 'D' -and (Get-Selected) -and -not $script:TrophyMode) { $sg = Get-Selected; Set-Favorite $sg (-not $sg.favorite); $k.SuppressKeyPress = $true }
        elseif ($k.KeyCode -eq 'F2') { Invoke-GameSettings; $k.SuppressKeyPress = $true }
        elseif ($k.KeyCode -eq 'F1') { Show-SetupAssistant; Refresh-List; $k.SuppressKeyPress = $true }
        elseif ($k.KeyCode -eq 'F11') { Show-TvMode; $k.SuppressKeyPress = $true }
        elseif ($k.KeyCode -eq 'Delete' -and $lv.Focused) { Invoke-RemoveGame; $k.SuppressKeyPress = $true }
        elseif ($k.KeyCode -eq 'Escape' -and $txtSearch.Focused) { $txtSearch.Text = ''; [void]$lv.Focus(); $k.SuppressKeyPress = $true }
        elseif ($k.KeyCode -eq 'Down' -and $txtSearch.Focused) { [void]$lv.Focus(); $k.SuppressKeyPress = $true }
    })

# ordem de encaixe: barra de baixo, barra de cima, painel do jogo (altura toda) e abas só em cima da biblioteca
$libPanel.Controls.Add($recentBar)
$form.Controls.Add($trophyView)
$form.Controls.Add($tabsBar)
$form.Controls.Add($detail)
$form.Controls.Add($top)
$form.Controls.Add($bottom)
$form.Controls.Add($toast)

function Set-Status([string]$t) { $lblStatus.Text = $t }

function Refresh-List {
    # mantém o jogo escolhido depois de refazer a lista (o painel do jogo continua nele)
    $keep = Get-Selected
    $script:InRefresh = $true
    $script:HotIndex = -1
    $script:CardAnim.Clear()
    $lv.BeginUpdate()
    $lv.Items.Clear()
    $f = $txtSearch.Text.Trim()
    foreach ($g in (Get-SortedGames)) {
        if ($f -and $g.name -notlike "*$f*") { continue }
        if (-not (Test-InTab $g $script:ConsoleFilter)) { continue }
        $it = New-Object System.Windows.Forms.ListViewItem($g.name)
        [void]$it.SubItems.Add($g.console)
        [void]$it.SubItems.Add((Get-GameSettings $g).preset)
        [void]$it.SubItems.Add($g.path)
        # na grade o console já aparece na etiqueta da capa: nome em branco fica mais limpo
        if ($script:ViewMode -ne 'lista') { $it.ForeColor = $fg }
        elseif ($consoleColors.ContainsKey($g.console)) { $it.ForeColor = $consoleColors[$g.console] }
        $it.Tag = $g
        $it.ImageKey = Get-CoverImageKey $g
        [void]$lv.Items.Add($it)
        if ($keep -and $g.path -eq $keep.path) { $it.Selected = $true; $it.Focused = $true }
    }
    # nada escolhido: começa no primeiro jogo, para o painel já mostrar algo
    if ($lv.SelectedItems.Count -eq 0 -and $lv.Items.Count -gt 0) { $lv.Items[0].Selected = $true; $lv.Items[0].Focused = $true }
    $lv.EndUpdate()
    if ($lv.SelectedItems.Count -gt 0) { $lv.SelectedItems[0].EnsureVisible() }
    $script:InRefresh = $false
    $libBackTimer.Stop(); $libBackTimer.Start()   # fundo com a arte do jogo escolhido
    Update-ConsoleTabs
    Update-RecentStrip
    Update-EmptyState
    Update-DetailPanel
    # jogo novo: prepara os troféus já, sem esperar a pessoa abrir a aba Conquistas
    if (@($script:Cfg.games).Count -ne $script:Ps4TextCount) {
        $script:Ps4TextCount = @($script:Cfg.games).Count
        try { Start-Ps4TextRefresh } catch { Write-AppLog "Nomes de troféus: $($_.Exception.Message)" }
    }
}

function Get-Selected {
    if ($lv.SelectedItems.Count -gt 0) { return $lv.SelectedItems[0].Tag }
    return $null
}

function Play-Selected {
    # na aba Conquistas, JOGAR volta para a biblioteca no jogo que estava escolhido
    if ($script:TrophyMode) { Set-ConsoleFilter $script:ConsoleFilter; return }
    $g = Get-Selected
    if (-not $g) { Show-Toast 'Escolha um jogo primeiro' 'info'; return }
    if ($script:RunDir) { Show-Toast 'Já existe um jogo ou emulador aberto' 'warn'; return }
    if ($script:Cfg.showSettings) {
        $r = Show-GameSettings $g $true
        Refresh-List
        if ($r -ne 'play') { return }
    }
    Start-Game $g
    Update-DetailPanel
}

# teclas de volume durante o jogo (só quando a janela do jogo está em foco); segurar repete
$VolKeysDown = @(0x6D, 0xBD)   # - do teclado numérico, - ao lado do 0
$VolKeysUp = @(0x6B, 0xBB)     # + do teclado numérico, = / + ao lado do -
$volTimer = New-Object System.Windows.Forms.Timer
$volTimer.Interval = 50
$volTimer.Add_Tick({
        $dir = 0
        foreach ($k in $VolKeysDown) { if ([PL.Audio]::KeyDown($k)) { $dir = -1 } }
        foreach ($k in $VolKeysUp) { if ([PL.Audio]::KeyDown($k)) { $dir = 1 } }
        if ($dir -eq 0) { $script:VolKeyHeld = 0; return }
        $script:VolKeyHeld++
        # 1ª batida na hora; segurando, repete depois de ~0,5 s a cada ~0,25 s
        if ($script:VolKeyHeld -ne 1 -and ($script:VolKeyHeld -lt 10 -or $script:VolKeyHeld % 5 -ne 0)) { return }
        if ($script:RunPids -notcontains [PL.Audio]::ForegroundPid()) { return }
        Set-GameVolume ($script:RunVolume + 10 * $dir) $true
    })

# save automático do PS2 (intervalo definido ao abrir o jogo)
$autoTimer = New-Object System.Windows.Forms.Timer
$autoTimer.Add_Tick({
        if (-not $script:RunDir) { $autoTimer.Stop(); return }
        if (Save-Pcsx2AutoState) { Set-Status "Save automático feito às $((Get-Date).ToString('HH:mm'))." }
    })

# monitora o emulador: aplica prioridade alta e restaura o plano de energia ao fechar
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.Add_Tick({
        if (-not $script:RunDir) { $timer.Stop(); return }
        $procs = @(Get-RunProcs)
        if ($procs.Count -gt 0) {
            $script:EmptyTicks = 0
            $script:RunPids = @($procs | ForEach-Object { $_.Id })
            Update-TriviumRun
            # o emulador só cria a saída de áudio depois de abrir o jogo: reaplica o volume escolhido
            if ($script:RunMode -eq 'game' -and $script:RunVolume -ne 100) { Set-GameVolume $script:RunVolume $false }
            # traz a janela do jogo para a frente: em tela cheia sem foco a barra de tarefas fica por cima
            if (-not $script:Focused -and $script:RunMode -eq 'game') {
                foreach ($p in $procs) {
                    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { Release-LaunchOverlay $p.MainWindowHandle; [void][PL.Win]::SetForegroundWindow($p.MainWindowHandle); $script:Focused = $true; break }
                }
            }
            if ($script:RunPriority) {
                foreach ($p in $procs) {
                    try { if ($p.PriorityClass -ne 'High') { $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High } } catch {}
                }
            }
            return
        }
        # alguns launchers fecham antes do jogo abrir: espera alguns ciclos antes de considerar encerrado
        $script:EmptyTicks++
        if ($script:EmptyTicks -lt 4) { return }
        $timer.Stop()
        $volTimer.Stop()
        $autoTimer.Stop()
        # fechou normalmente (código 0): tira a marca de "jogo aberto"; com erro, a marca fica para oferecer o save automático
        $code = $null
        try { if ($script:RunProc.HasExited) { $code = $script:RunProc.ExitCode } } catch {}
        if ($script:RunGame -and $script:RunGame.running -and $code -eq 0) { Set-GameRunningFlag $script:RunGame $false }
        $mode = $script:RunMode
        $script:RunDir = $null
        if ($script:TvForm -and $script:TvForm.Visible) { Start-TvAnim }
        # guarda o volume do jogo para a próxima vez
        $g = $script:RunGame
        $secs = 0
        if ($mode -eq 'game' -and $g) { $secs = [int]((Get-Date) - $script:RunStart).TotalSeconds; Add-PlayTime $g $secs }
        if ($mode -eq 'game' -and $g) {
            try {
                Update-Ps4TrophyWatch; $script:TrophyWatch = $null
                Show-TriviumAlerts $g (Update-TriviumAch $g $secs 0)
                if ($script:TrophyMode) { Update-TrophyData; Update-TrophyGames }
            } catch { Write-AppLog "Conquistas: $($_.Exception.Message)" }
        }
        if ($mode -eq 'game' -and $g -and (Split-Path $script:RunEmuExe -Leaf) -eq 'pcsx2-qt.exe') { Save-RaGameId $g $script:RunEmuExe; $script:RaLastFetch = $null }
        # depois de jogar: backup automático dos saves (um por dia)
        if ($mode -eq 'game') { Invoke-AutoBackup }
        Close-LaunchOverlay
        if ($mode -eq 'game' -and $g -and [int](Get-GameSettings $g).volume -ne $script:RunVolume) {
            $h = [ordered]@{}
            if ($g.settings) { foreach ($prop in $g.settings.PSObject.Properties) { $h[$prop.Name] = $prop.Value } }
            $h.volume = $script:RunVolume
            $g | Add-Member -NotePropertyName settings -NotePropertyValue ([pscustomobject]$h) -Force
            Save-Config
        }
        $script:RunGame = $null
        Restore-PowerPlan
        Restore-Vibrance
        Update-DetailPanel
        # volta para o modo TV se o jogo foi aberto por ele
        if ($script:TvForm -and $script:TvForm.Visible) { $script:TvForm.Activate(); $script:TvForm.Invalidate() }
        else { $form.WindowState = 'Normal'; $form.Activate() }
        if ($mode -eq 'setup') { Set-Status 'Emulador fechado. Agora é só clicar em JOGAR.'; Show-Toast 'Emulador fechado. Agora é só clicar em JOGAR' 'info' }
        else {
            Set-Status 'Jogo encerrado. Configurações de energia restauradas.'
            # fechou com erro, ou logo depois de abrir: explica e oferece tentar com configurações seguras
            # (só para os emuladores abertos direto; ports nativos têm launcher próprio que fecha sozinho)
            $crash = ($null -ne $code) -and ($code -ne 0 -or $secs -lt 12)
            # falha nos primeiros segundos de um jogo de PS4 acontece de vez em quando e some ao abrir de novo: reabre sozinho
            if ($secs -ge 20) { $script:QuickRetry = 0 }
            if ($g -and $null -ne $code -and $code -ne 0 -and $secs -lt 20 -and (Get-ConsoleKind $g) -eq 'PS4' -and [int]$script:QuickRetry -lt 2) {
                $script:QuickRetry = [int]$script:QuickRetry + 1
                Write-AppLog "Jogo fechou com o código $code em $secs s: abrindo de novo ($($script:QuickRetry) de 2)"
                Show-Toast 'O jogo falhou ao abrir: tentando de novo' 'warn'
                Start-Game $g
                return
            }
            $script:QuickRetry = 0
            if ($crash -and $g -and (Split-Path $script:RunEmuExe -Leaf) -in 'pcsx2-qt.exe', 'rpcs3.exe', 'shadPS4.exe', 'shadps4-eltutz.exe') {
                Show-CrashDialog $g $script:RunEmuExe $code $secs $script:RunStart
            } elseif ($secs -ge 60) { Show-Toast "Jogo encerrado: $(Format-PlayTime $secs) nesta sessão" 'ok' }
        }
    })

function Invoke-GameSettings {
    $g = Get-Selected
    if (-not $g) { Show-Toast 'Escolha um jogo primeiro' 'info'; return }
    if ((Show-GameSettings $g $false) -ne 'cancel') { Set-Status "Configurações salvas: $($g.name)"; Show-Toast 'Configurações salvas' 'ok' }
    Refresh-List
}

function Invoke-AddFiles {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = L 'Selecione ISO / PKG / EBOOT.BIN (PS3) / eboot.bin (PS4)'
    $dlg.Filter = L 'Jogos PS2/PS3/PS4|*.iso;*.chd;*.cso;*.zso;*.gz;*.bin;*.mdf;*.img;*.pkg|Todos|*.*'
    $dlg.Multiselect = $true
    if ($dlg.ShowDialog() -eq 'OK') { Add-Games $dlg.FileNames }
}

function Invoke-AddFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = L 'Escolha uma pasta de jogo (ex: CUSA01623) ou uma pasta com vários jogos'
    if ($dlg.ShowDialog() -eq 'OK') { Add-Games @($dlg.SelectedPath) }
}

$btnPlay.Add_Click({ Play-Selected })
$lv.Add_DoubleClick({ Play-Selected })
$lv.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { Play-Selected } })
$btnSettings.Add_Click({ Invoke-GameSettings })
$btnEmus.Add_Click({ Show-EmulatorsDialog })
$btnAch.Add_Click({ Show-TrophyView })
$btnAddFile.Add_Click({ Invoke-AddFiles })
$btnAddDir.Add_Click({ Invoke-AddFolder })
$btnRemove.Add_Click({ Invoke-RemoveGame })

function Invoke-RemoveGame {
        $g = Get-Selected
        if (-not $g) { return }
        $script:Cfg.games = @($script:Cfg.games | Where-Object { $_.path -ne $g.path })
        Save-Config; Refresh-List
        Set-Status "Removido da lista: $($g.name) (o arquivo não foi apagado)"
        # sem caixa de confirmação: o aviso traz "Desfazer" por alguns segundos
        $script:LastRemoved = $g
        Show-Toast "Removido da lista: $($g.name)" 'info' 'Desfazer' {
            $r = $script:LastRemoved
            if (-not $r -or @($script:Cfg.games | Where-Object { $_.path -eq $r.path }).Count) { return }
            $script:Cfg.games = @($script:Cfg.games) + $r
            Save-Config; Refresh-List; Select-Game $r
            $script:LastRemoved = $null
            Show-Toast "$($r.name) voltou para a biblioteca" 'ok'
        }
}

$txtSearch.Add_TextChanged({ if ($script:TrophyMode) { Update-TrophyGames } else { Refresh-List } })

$form.Add_DragEnter({ if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$form.Add_DragDrop({ Add-Games ([string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) })
$lv.AllowDrop = $true
$lv.Add_DragEnter({ if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$lv.Add_DragDrop({ Add-Games ([string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) })

$form.Add_FormClosing({
        # instalação de PKG pela metade: para o PkgTool e apaga o que ficou incompleto
        if ($script:PkgJob) { Stop-PkgInstall $true }
        Restore-PowerPlan; Restore-Vibrance
        Close-LaunchOverlay
        # guarda tamanho e posição da janela
        $rb = if ($form.WindowState -eq 'Normal') { $form.Bounds } else { $form.RestoreBounds }
        $script:Cfg.windowBounds = "$($rb.X),$($rb.Y),$($rb.Width),$($rb.Height)"
        $script:Cfg.windowMax = $form.WindowState -eq 'Maximized'
        Save-Config
    })
$form.Add_Shown({
        # fecha a tela de abertura antes de qualquer aviso (ela fica por cima de tudo)
        $splash.Close(); $splash.Dispose()
        if ($script:PlayFxOk) { [PL.PlayFx]::CloseSplash() }
        $form.Activate()
        Set-LibraryView $script:ViewMode
        # primeiros passos: na primeira vez (ou enquanto a pessoa quiser) e sempre que não houver emulador nenhum
        $missing = @($EmuKeys | Where-Object { -not $script:Cfg[$_] -or -not (Test-Path -LiteralPath $script:Cfg[$_]) })
        if ($script:Cfg.showWelcome -or $missing.Count -eq $EmuKeys.Count) { Show-SetupAssistant; Refresh-List }
    })

$script:ViewMode = if ($script:Cfg.viewMode -eq 'lista') { 'lista' } else { 'grade' }
if ($script:Cfg.consoleFilter -in $TabNames) { $script:ConsoleFilter = $script:Cfg.consoleFilter }
Set-SortMode $script:Cfg.sortMode
Set-CoverSize $script:Cfg.coverSize $false
Refresh-List
$form.Add_Shown({
        $padTimer.Start()
        $script:DetailReady = $true
        Update-DetailPanel
        # texto de ajuda dentro da busca (EM_SETCUEBANNER), some quando a pessoa digita
        [void][PL.Cue]::SendMessage($txtSearch.Handle, 0x1501, [IntPtr]1, (L 'Buscar jogo...'))
        & $script:LayoutSearch
        [void]$lv.Focus()
        # procura versão nova do launcher uma vez por dia, em segundo plano
        if ($script:Cfg.lastUpdateCheck -ne (Get-Date).ToString('yyyy-MM-dd')) { Start-UpdateCheck }
    })
Set-Status 'Arraste ISO / PKG / pastas de jogos (PS2, PS3 ou PS4) para a janela. Duplo clique para jogar.'
# Application.Run em vez de ShowDialog: com ShowDialog a janela vira "filha" da tela de abertura e some quando ela fecha
# inglês: traduz a janela principal e os menus (o que mudar depois é traduzido na hora)
[PL.Lang]::Hook($form); [PL.Lang]::HookMenu($gameMenu); [PL.Lang]::HookMenu($sortMenu)
[System.Windows.Forms.Application]::Run($form)
