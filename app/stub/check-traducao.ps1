# Confere o Launcher.ps1 contra idiomas\en.txt: lista os textos em português sem tradução.
# Rode depois de mudar textos do launcher. Sai com código 1 se faltar alguma tradução.
$app = Split-Path (Split-Path $MyInvocation.MyCommand.Path)
$src = Join-Path $app 'Launcher.ps1'
$dict = @{}; $pats = @()
foreach ($raw in [IO.File]::ReadAllLines((Join-Path $app 'idiomas\en.txt'), [Text.Encoding]::UTF8)) {
    $line = $raw.TrimEnd(); if (-not $line -or $line.StartsWith('#')) { continue }
    $i = $line.IndexOf(' => '); if ($i -lt 0) { continue }
    $a = $line.Substring(0, $i).Replace('\n', "`n")
    if ($a.StartsWith('re: ')) { $pats += New-Object regex($a.Substring(4), 'Singleline') } else { $dict[$a.Trim()] = 1 }
}
# mesma ordem do tradutor do launcher: frase inteira, depois parte por parte
function Has([string]$t) {
    $t = $t.Trim().Replace("`r`n", "`n")
    if (-not $t -or $dict.ContainsKey($t)) { return $true }
    foreach ($p in $pats) { if ($p.IsMatch($t)) { return $true } }
    foreach ($sep in "`n", [string][char]0x2022, [string][char]0xB7, '|') {
        if ($t.Contains($sep)) {
            foreach ($part in $t.Split([char]$sep)) { if ((Looks $part) -and -not (Has $part)) { return $false } }
            return $true
        }
    }
    return $false
}
function Looks([string]$t) {
    $x = $t.Trim()
    if ($x -notmatch '[A-Za-zÀ-ÿ]{2}') { return $false }
    if ($x -match '^(https?:|[A-Z]:\\|\^|\(\?|-[a-zA-Z]+ |\*\.|<)|\\[dswb.(]|\(\?|[{}\[\]^]{2,}|\.(ps1|exe|ini|json|dll|log|xml|txt|bin|zip)$') { return $false }
    if ($x -match '[À-ÿ]') { return $true }
    # sem acento: precisa ter jeito de português
    return ($x -match '(?i)\b(o|a|os|as|um|uma|de|do|da|dos|das|em|no|na|nos|nas|para|por|com|sem|que|se|ou|e|jogo|jogos|arquivo|arquivos|pasta|erro|falta|ainda|agora|depois|todos|sim|ver|tela|som)\b|(?i)(ado|ada|ados|adas|ando|endo|ar|ir)(\.{3})?$')
}
$errs = $null; $toks = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($src, [ref]$toks, [ref]$errs)
$found = [ordered]@{}
# não aparecem na tela, ou ficam iguais em inglês, ou são pedaços de frases que o dicionário tem inteiras
$ignore = 'ps4InstallDir', 'ROMDIR', '60FPS++ (no deltatime)', '--no-gui', 'HighQualityBilinear', 'Bilinear', 'adicionados', 'No',
    'Português', 'Automático (Windows) / Automatic', 'limite de tradução', 'TriviumHub/1.0 (launcher de jogos)', 'instalado', 'sim', 'FALTA', 'conectado',
    'NÃO (shadPS4 eltutz não funciona)', 'NÃO (atualize o driver da placa de vídeo)', '(ainda não escolhida)', ', patch de texturas'
# as variáveis do texto viram 0: tenta também com valores reais
function Filled([string]$v) {
    if (Has $v) { return $true }
    foreach ($try in 'PS2', '100%', '0x1') { if (Has ([regex]::Replace($v, '(?<![\d.])0(?![\d.])', $try))) { return $true } }
    return $false
}
function Check([string]$v, [int]$line) { if ((Looks $v) -and $ignore -notcontains $v.Trim() -and $v -notmatch '^\$|\.instalando$|^Gerado pelo|\$\(if|\{0|^ nos jogos de|^N.o h. jogo com esse nome0|^Nenhum jogo encontrado|^N.O abre|^BIOS do PS2: 0|^0 : 0 jogos' -and -not (Filled $v) -and -not $found.Contains($v)) { $found[$v] = $line } }
function Text($n) {
    if ($n -is [Management.Automation.Language.StringConstantExpressionAst]) { return $n.Value }
    if ($n -is [Management.Automation.Language.ExpandableStringExpressionAst]) { return ([regex]::Replace($n.Extent.Text.Trim('"'), '\$\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)|\$\{?[\w:]+\}?(\[[^\]]*\])?', '0')).Replace('`n', "`n").Replace('""', '"').Replace('`"', '"') }
    return $null
}
foreach ($n in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.CommandAst] -or $x -is [Management.Automation.Language.BinaryExpressionAst] }, $true)) {
    # frase quebrada em partes com +
    if ($n -is [Management.Automation.Language.BinaryExpressionAst] -and $n.Operator -eq 'Plus') {
        if ($n.Parent -is [Management.Automation.Language.BinaryExpressionAst]) { continue }
        $parts = New-Object Collections.ArrayList
        $walk = { param($b) foreach ($k in $b.Left, $b.Right) { if ($k -is [Management.Automation.Language.BinaryExpressionAst]) { & $walk $k } else { [void]$parts.Add((Text $k)) } } }
        & $walk $n
        if ($parts -notcontains $null) { Check ($parts -join '') $n.Extent.StartLineNumber }
    }
}
$skip = '^(Write-AppLog|Add-Type|New-Object|Join-Path|Get-Process|Test-Path|Get-Item|Get-ChildItem|Get-Content|Remove-Item|Copy-Item|New-Item|Move-Item|Select-Object|Where-Object|ForEach-Object)\b'
foreach ($n in $ast.FindAll({ param($x) $x -is [Management.Automation.Language.StringConstantExpressionAst] -or $x -is [Management.Automation.Language.ExpandableStringExpressionAst] }, $true)) {
    if ($n.Extent.Text -match "^@['""]") { continue }   # blocos C#
    if ($n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'BareWord') { continue }
    if ($n.Parent -is [Management.Automation.Language.ExpandableStringExpressionAst]) { continue }
    $bin = $n.Parent; $inPlus = $false
    while ($bin -is [Management.Automation.Language.BinaryExpressionAst]) { if ($bin.Operator -eq 'Plus') { $inPlus = $true }; $bin = $bin.Parent }
    if ($inPlus) { continue }
    $c = $n.Parent; while ($c -and -not ($c -is [Management.Automation.Language.CommandAst])) { if ($c -is [Management.Automation.Language.StatementBlockAst]) { $c = $null; break }; $c = $c.Parent }
    if ($c -and $c.Extent.Text -match $skip) { continue }
    Check (Text $n) $n.Extent.StartLineNumber
}
foreach ($k in $found.Keys) { "$($found[$k]): $($k -replace "`n", '\n')" }
"$($found.Count) texto(s) sem tradução; dicionário com $($dict.Count) frases e $($pats.Count) padrões"
if ($found.Count) { exit 1 }
