# Gera a logo do Trivium Hub (mesmo símbolo do ícone: o T de três caminhos, uma peça por console + nome)
# Uso: make-logo.ps1 -Out logo.png [-Height 160] [-Square] [-Tagline 'texto'] [-Background]
param([string]$Out, [int]$Height = 160, [switch]$Square, [string]$Tagline = 'PS2  ·  PS3  ·  PS4', [switch]$Background)
Add-Type -AssemblyName System.Drawing

function Add-TrioPiece($g, [single]$cx, [single]$cy, [single]$s, [single[]]$xy, $c, [single]$angle) {
    $pts = New-Object 'System.Drawing.PointF[]' ($xy.Count / 2)
    for ($k = 0; $k -lt $pts.Count; $k++) { $pts[$k] = New-Object System.Drawing.PointF(($cx + $xy[$k * 2] * $s / 2), ($cy + $xy[$k * 2 + 1] * $s / 2)) }
    $top = [System.Drawing.Color]::FromArgb(($c.R + (255 - $c.R) * 0.42), ($c.G + (255 - $c.G) * 0.42), ($c.B + (255 - $c.B) * 0.42))
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon($pts)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($p.GetBounds(), $top, $c, $angle)
    $g.FillPath($b, $p)
}

function Draw-Emblem($g, [single]$cx, [single]$cy, [single]$s) {
    # $s = tamanho do símbolo; PS2 azul (braço esquerdo), PS3 vermelho (direito), PS4 verde (haste)
    Add-TrioPiece $g $cx $cy $s @(-.98, -.80, -.055, -.80, -.055, -.14, -.30, -.34, -.82, -.34) ([System.Drawing.Color]::FromArgb(70, 136, 255)) 20
    Add-TrioPiece $g $cx $cy $s @(.98, -.80, .055, -.80, .055, -.14, .30, -.34, .82, -.34) ([System.Drawing.Color]::FromArgb(255, 70, 92)) 160
    Add-TrioPiece $g $cx $cy $s @(0, -.06, .28, -.27, .28, .62, 0, .96, -.28, .62, -.28, -.27) ([System.Drawing.Color]::FromArgb(44, 210, 140)) 90
}

function Fill-Back($g, [int]$w, [int]$h) {
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
        [System.Drawing.Color]::FromArgb(40, 40, 54), [System.Drawing.Color]::FromArgb(14, 14, 20), 90)
    $g.FillRectangle($lg, 0, 0, $w, $h)
}

$white = [System.Drawing.Color]::FromArgb(245, 245, 250)
$dim = [System.Drawing.Color]::FromArgb(160, 165, 185)
if ($Square) {
    # quadrada (perfil, capa de vídeo, ícone grande): símbolo em cima, nome embaixo
    $W = $Height; $H = $Height
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    if ($Background) { Fill-Back $g $W $H } else { $g.Clear([System.Drawing.Color]::Transparent) }
    Draw-Emblem $g ($W / 2) ($H * 0.40) ($H * 0.62)
    $f1 = New-Object System.Drawing.Font('Segoe UI', [single]($H * 0.085), [System.Drawing.FontStyle]::Bold, 'Pixel')
    $f2 = New-Object System.Drawing.Font('Segoe UI', [single]($H * 0.040), [System.Drawing.FontStyle]::Regular, 'Pixel')
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'
    $g.DrawString('TRIVIUM HUB', $f1, (New-Object System.Drawing.SolidBrush($white)), (New-Object System.Drawing.RectangleF(0, [single]($H * 0.73), $W, [single]($H * 0.12))), $sf)
    $g.DrawString($Tagline, $f2, (New-Object System.Drawing.SolidBrush($dim)), (New-Object System.Drawing.RectangleF(0, [single]($H * 0.855), $W, [single]($H * 0.08))), $sf)
} else {
    # horizontal (cabeçalho, banner): símbolo à esquerda, nome e linha de baixo à direita
    $H = $Height
    $f1 = New-Object System.Drawing.Font('Segoe UI', [single]($H * 0.36), [System.Drawing.FontStyle]::Bold, 'Pixel')
    $f2 = New-Object System.Drawing.Font('Segoe UI', [single]($H * 0.15), [System.Drawing.FontStyle]::Regular, 'Pixel')
    $tmp = New-Object System.Drawing.Bitmap(1, 1); $tg = [System.Drawing.Graphics]::FromImage($tmp)
    $tw = [math]::Max($tg.MeasureString('TRIVIUM HUB', $f1).Width, $tg.MeasureString($Tagline, $f2).Width)
    $W = [int]($H * 1.05 + $tw + $H * 0.15)
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
    if ($Background) { Fill-Back $g $W $H } else { $g.Clear([System.Drawing.Color]::Transparent) }
    Draw-Emblem $g ($H * 0.5) ($H * 0.52) ($H * 0.92)
    $x = [single]($H * 1.0)
    $g.DrawString('TRIVIUM HUB', $f1, (New-Object System.Drawing.SolidBrush($white)), $x, [single]($H * 0.17))
    $g.DrawString($Tagline, $f2, (New-Object System.Drawing.SolidBrush($dim)), [single]($x + $H * 0.03), [single]($H * 0.62))
}
$g.Dispose()
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"ok $Out  $($bmp.Width)x$($bmp.Height)"
