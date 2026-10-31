param([string]$Out, [string]$Preview)
Add-Type -AssemblyName System.Drawing

function Add-TrioPiece($g, [single]$cx, [single]$cy, [single]$s, [single[]]$xy, $c, [single]$angle) {
    $pts = New-Object 'System.Drawing.PointF[]' ($xy.Count / 2)
    for ($k = 0; $k -lt $pts.Count; $k++) { $pts[$k] = New-Object System.Drawing.PointF(($cx + $xy[$k * 2] * $s / 2), ($cy + $xy[$k * 2 + 1] * $s / 2)) }
    $top = [System.Drawing.Color]::FromArgb(($c.R + (255 - $c.R) * 0.42), ($c.G + (255 - $c.G) * 0.42), ($c.B + (255 - $c.B) * 0.42))
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath; $p.AddPolygon($pts)
    $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush($p.GetBounds(), $top, $c, $angle)
    $g.FillPath($b, $p)
}

function New-IconBitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
    $g.Clear([System.Drawing.Color]::Transparent)
    # fundo: quadrado arredondado escuro com degradê (como a tela de abertura)
    $r = [single]($s * 0.22); $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $m = [single]([math]::Max(0.5, $s * 0.02)); $w = [single]($s - 2 * $m)
    $p.AddArc($m, $m, 2 * $r, 2 * $r, 180, 90); $p.AddArc($m + $w - 2 * $r, $m, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($m + $w - 2 * $r, $m + $w - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($m, $m + $w - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure()
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.RectangleF(0, 0, $s, $s)),
        [System.Drawing.Color]::FromArgb(48, 48, 64), [System.Drawing.Color]::FromArgb(14, 14, 20), 90)
    $g.FillPath($lg, $p)
    # o T de três caminhos: PS2 azul (braço esquerdo), PS3 vermelho (direito), PS4 verde (haste)
    Add-TrioPiece $g ($s / 2) ($s * 0.49) ($s * 0.84) @(-.98, -.80, -.055, -.80, -.055, -.14, -.30, -.34, -.82, -.34) ([System.Drawing.Color]::FromArgb(70, 136, 255)) 20
    Add-TrioPiece $g ($s / 2) ($s * 0.49) ($s * 0.84) @(.98, -.80, .055, -.80, .055, -.14, .30, -.34, .82, -.34) ([System.Drawing.Color]::FromArgb(255, 70, 92)) 160
    Add-TrioPiece $g ($s / 2) ($s * 0.49) ($s * 0.84) @(0, -.06, .28, -.27, .28, .62, 0, .96, -.28, .62, -.28, -.27) ([System.Drawing.Color]::FromArgb(44, 210, 140)) 90
    $g.Dispose()
    return $bmp
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$pngs = foreach ($s in $sizes) { $b = New-IconBitmap $s; $ms = New-Object IO.MemoryStream; $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); , $ms.ToArray() }
# arquivo .ico: cabeçalho + uma entrada por tamanho + as imagens PNG
$fs = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$off = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$off)
    $off += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
[IO.File]::WriteAllBytes($Out, $fs.ToArray())
# prévia: os tamanhos lado a lado
$pv = New-Object System.Drawing.Bitmap(560, 280); $pg = [System.Drawing.Graphics]::FromImage($pv); $pg.Clear([System.Drawing.Color]::FromArgb(32, 32, 36))
$x = 10; foreach ($s in 16, 24, 32, 48, 64, 128, 256) { $b = New-IconBitmap $s; $pg.DrawImage($b, $x, 10, $s, $s); $x += $s + 10; $b.Dispose() }
$pv.Save($Preview); "ok $((Get-Item $Out).Length) bytes"
