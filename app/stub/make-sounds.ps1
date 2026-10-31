# Gera os sons do Trivium Hub em app\sons: trofeu.wav (conquista), platina.wav (platina) e abertura.wav (abertura do launcher).
# Sons originais, sintetizados do zero, sem nenhuma amostra de áudio.
# Uso: make-sounds.ps1 -Out ..\sons
param([string]$Out)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class TriviumSound {
    const int Rate = 44100;
    static void Bell(double[] l, double[] r, double start, double freq, double gain, double decay, double pan) {
        int s0 = (int)(start * Rate);
        for (int i = s0; i < l.Length; i++) {
            double t = (i - s0) / (double)Rate;
            double attack = Math.Min(1, t / .012); attack = attack * attack * (3 - 2 * attack);
            double env = attack * Math.Exp(-t / decay);
            if (env < .0002 && t > .05) break;
            double index = .8 * Math.Exp(-t / .08);
            double v = Math.Sin(2 * Math.PI * freq * t + index * Math.Sin(2 * Math.PI * freq * 3.01 * t));
            v += .16 * Math.Sin(2 * Math.PI * freq * 2 * t) * Math.Exp(-t / (decay * .45));
            l[i] += v * env * gain * (1 - pan * .5);
            r[i] += v * env * gain * (1 + pan * .5);
        }
    }
    // base quente que cresce devagar: é ela que dá o peso de recompensa
    static void Pad(double[] l, double[] r, double start, double freq, double gain, double rise, double decay) {
        int s0 = (int)(start * Rate);
        for (int i = s0; i < l.Length; i++) {
            double t = (i - s0) / (double)Rate;
            double env = (1 - Math.Exp(-t / rise)) * Math.Exp(-t / decay) * gain;
            double a = Math.Sin(2 * Math.PI * freq * 1.003 * t) + .4 * Math.Sin(2 * Math.PI * freq * 2 * t);
            double b = Math.Sin(2 * Math.PI * freq * .997 * t) + .4 * Math.Sin(2 * Math.PI * freq * 2.004 * t);
            l[i] += a * env; r[i] += b * env;
        }
    }
    // pontinhos de brilho subindo no fim
    static void Sparkle(double[] l, double[] r, double start, double[] notes, double step, double gain) {
        for (int k = 0; k < notes.Length; k++)
            Bell(l, r, start + k * step, notes[k], gain * (1 - k * .06), .22, k % 2 == 0 ? -.7 : .7);
    }
    static void Soft(double[] x, double hz) {
        double a = 1 - Math.Exp(-2 * Math.PI * hz / Rate), s1 = 0, s2 = 0;
        for (int i = 0; i < x.Length; i++) { s1 += a * (x[i] - s1); s2 += a * (s1 - s2); x[i] = s2; }
    }
    static void Space(double[] l, double[] r, double amount) {
        int[] taps = { 3307, 5203, 7919, 11177, 15101, 19891 };
        double[] gains = { .24, .19, .14, .10, .07, .05 };
        var a = (double[])l.Clone(); var b = (double[])r.Clone();
        for (int k = 0; k < taps.Length; k++)
            for (int i = taps[k]; i < l.Length; i++) {
                l[i] += b[i - taps[k]] * gains[k] * amount;
                r[i] += a[i - taps[k]] * gains[k] * amount;
            }
    }
    static byte[] Wave(double[] l, double[] r, double level, int tail) {
        int n = l.Length; double peak = 0;
        for (int i = 0; i < n; i++) peak = Math.Max(peak, Math.Max(Math.Abs(l[i]), Math.Abs(r[i])));
        double k = level / peak;
        var ms = new MemoryStream(); var w = new BinaryWriter(ms);
        int bytes = n * 4;
        w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + bytes); w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
        w.Write(16); w.Write((short)1); w.Write((short)2); w.Write(Rate); w.Write(Rate * 4); w.Write((short)4); w.Write((short)16);
        w.Write(Encoding.ASCII.GetBytes("data")); w.Write(bytes);
        for (int i = 0; i < n; i++) {
            double fade = i > n - tail ? (n - i) / (double)tail : 1;
            w.Write((short)(l[i] * k * fade * 32767)); w.Write((short)(r[i] * k * fade * 32767));
        }
        return ms.ToArray();
    }
    // conquista: três notas rápidas, acorde com peso embaixo e um brilho curto subindo
    public static byte[] Trophy() {
        int n = (int)(1.15 * Rate); double[] l = new double[n], r = new double[n];
        double a4 = 440, e5 = 659.25, a5 = 880, cs6 = 1108.73, e6 = 1318.51;
        Pad(l, r, .13, 110, .13, .05, .30);
        Pad(l, r, .13, 220, .07, .04, .26);
        Bell(l, r, 0.00, a4, .36, .16, -.5);
        Bell(l, r, 0.07, e5, .38, .16, .5);
        Bell(l, r, 0.14, a5, .48, .28, 0);
        Bell(l, r, 0.15, cs6, .26, .30, -.3);
        Bell(l, r, 0.16, e6, .22, .34, .3);
        Sparkle(l, r, .30, new[] { 1760.0, 2217.46, 2637.02 }, .055, .07);
        Space(l, r, 1); Soft(l, 3800); Soft(r, 3800);
        return Wave(l, r, .30, 9000);
    }
    // sopro que sobe junto com os cometas e some no impacto
    static void Rise(double[] l, double[] r, double end, double gain) {
        int n = (int)(end * Rate); var rnd = new Random(7);
        double a = 0, b = 0;
        for (int i = 0; i < n && i < l.Length; i++) {
            double t = i / (double)n, cut = 180 + 2600 * t * t, k = 1 - Math.Exp(-2 * Math.PI * cut / Rate);
            double x = rnd.NextDouble() * 2 - 1, y = rnd.NextDouble() * 2 - 1;
            a += k * (x - a); b += k * (y - b);
            double env = t * t * t * gain;
            l[i] += a * env; r[i] += b * env;
        }
    }
    // abertura do launcher: sincronizada com a animação, com o impacto quando os cometas viram o logo
    public static byte[] Intro() {
        int n = (int)(3.2 * Rate); double[] l = new double[n], r = new double[n];
        double hit = .86;
        Rise(l, r, hit, .55);
        double[] run = { 220, 329.63, 440, 554.37, 659.25 };
        for (int i = 0; i < run.Length; i++) Bell(l, r, .22 + i * .13, run[i], .15 + i * .035, .24, i % 2 == 0 ? -.5 : .5);
        foreach (var f in new[] { 55.0, 110.0 }) Pad(l, r, hit - .02, f, .15, .03, .75);
        foreach (var f in new[] { 220.0, 329.63, 440.0, 554.37 }) Pad(l, r, hit, f, .045, .10, .85);
        Bell(l, r, hit, 440, .46, .90, -.2);
        Bell(l, r, hit + .01, 554.37, .32, .95, .2);
        Bell(l, r, hit + .02, 659.25, .30, 1.0, -.3);
        Bell(l, r, hit + .03, 880, .28, 1.05, .3);
        Sparkle(l, r, hit + .34, new[] { 1318.51, 1760.0, 2217.46, 2637.02 }, .09, .055);
        Space(l, r, 1.5); Soft(l, 4200); Soft(r, 4200);
        return Wave(l, r, .30, 30000);
    }
    // platina: subida de cinco notas, um acorde grande que cresce e uma chuva de brilho
    public static byte[] Platinum() {
        int n = (int)(3.0 * Rate); double[] l = new double[n], r = new double[n];
        double[] run = { 293.66, 440, 587.33, 739.99, 880 };
        for (int i = 0; i < run.Length; i++) Bell(l, r, i * .10, run[i], .34 + i * .025, .30, i % 2 == 0 ? -.45 : .45);
        double hit = .50;
        foreach (var f in new[] { 73.42, 146.83 }) Pad(l, r, hit - .10, f, .13, .12, .95);
        foreach (var f in new[] { 293.66, 440.0, 587.33, 739.99 }) Pad(l, r, hit - .05, f, .055, .16, .80);
        Bell(l, r, hit, 587.33, .46, .80, -.2);
        Bell(l, r, hit, 739.99, .34, .85, .2);
        Bell(l, r, hit + .012, 880, .32, .90, -.3);
        Bell(l, r, hit + .024, 1174.66, .30, 1.0, .3);
        Bell(l, r, hit + .036, 1479.98, .20, 1.05, 0);
        Sparkle(l, r, hit + .22, new[] { 1760.0, 2349.32, 2959.96, 3520.0, 2959.96, 3520.0, 4698.64 }, .10, .065);
        Space(l, r, 1.5); Soft(l, 4800); Soft(r, 4800);
        return Wave(l, r, .34, 26000);
    }
}
'@
if (-not $Out) { $Out = Join-Path (Split-Path $MyInvocation.MyCommand.Path) '..\sons' }
New-Item -ItemType Directory -Force $Out | Out-Null
foreach ($s in @(@('trofeu.wav', [TriviumSound]::Trophy()), @('platina.wav', [TriviumSound]::Platinum()), @('abertura.wav', [TriviumSound]::Intro()))) {
    $p = Join-Path $Out $s[0]; [IO.File]::WriteAllBytes($p, [byte[]]$s[1])
    $b = [byte[]]$s[1]; $max = 0; for ($i = 44; $i -lt $b.Length; $i += 2) { $v = [math]::Abs([int][BitConverter]::ToInt16($b, $i)); if ($v -gt $max) { $max = $v } }
    "$($s[0]): $([math]::Round(($b.Length - 44) / 4 / 44100, 2)) s, pico $max"
}
