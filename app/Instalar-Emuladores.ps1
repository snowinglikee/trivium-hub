# Baixa (ou atualiza) os emuladores das paginas oficiais no GitHub para app\emuladores\
# Uso: Instalar-Emuladores.ps1 [-Only pcsx2,rpcs3,shadps4,pkgtool,shadps4eltutz] [-Force]
param([string[]]$Only, [switch]$Force, [string]$Lang = 'pt')

# mensagens em portugues ou ingles, conforme o idioma do launcher
function Say([string]$pt, [string]$en) { if ($Lang -eq 'en') { return $en } return $pt }

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle = Say 'Trivium Hub - instalando emuladores' 'Trivium Hub - installing emulators'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$EmuDir = Join-Path $Root 'emuladores'
$Tmp = Join-Path $env:TEMP 'TriviumHub-download'
New-Item -ItemType Directory -Force $EmuDir, $Tmp | Out-Null

$emus = [ordered]@{
    pcsx2       = @{ name = 'PCSX2 (PS2)'; repo = 'PCSX2/pcsx2'; asset = 'windows-x64-Qt\.7z$'; exe = 'pcsx2-qt.exe' }
    rpcs3       = @{ name = 'RPCS3 (PS3)'; repo = 'RPCS3/rpcs3-binaries-win'; asset = '_win64_msvc\.7z$'; exe = 'rpcs3.exe' }
    shadps4     = @{ name = 'shadPS4 (PS4)'; repo = 'shadps4-emu/shadPS4'; asset = 'win64-sdl.*\.zip$'; exe = 'shadPS4.exe' }
    # PkgTool (LibOrbisPkg, LGPL-3.0): instala PKG de PS4 direto pelo launcher, sem abrir o emulador
    pkgtool     = @{ name = (Say 'PkgTool (instalar PKG de PS4)' 'PkgTool (install PS4 PKGs)'); repo = 'maxton/LibOrbisPkg'; asset = '^PkgTool-[\d.]+\.zip$'; exe = 'PkgTool.exe' }
    # shadPS4 eltutz (cuesta4): um .exe so, na mesma pasta do shadPS4 oficial (usa a mesma pasta user)
    shadps4eltutz = @{ name = 'shadPS4 eltutz (cuesta4, God of War III)'; repo = 'cuesta4/shadPS4'; asset = '^shadps4-eltutz\.exe$'; exe = 'shadps4-eltutz.exe'; into = 'shadps4' }
}

function Get-7z {
    foreach ($p in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") {
        if ($p -and (Test-Path $p)) { return $p }
    }
    # 7zr.exe: extrator oficial e independente do 7-Zip (so le .7z)
    $7zr = Join-Path $Tmp '7zr.exe'
    if (-not (Test-Path $7zr)) {
        Write-Host (Say '  baixando 7zr.exe (7-zip.org) para extrair arquivos .7z...' '  downloading 7zr.exe (7-zip.org) to extract .7z files...')
        & curl.exe -L --fail -s -o $7zr 'https://www.7-zip.org/a/7zr.exe'
        if ($LASTEXITCODE -ne 0) { throw (Say 'falha ao baixar 7zr.exe' 'failed to download 7zr.exe') }
    }
    return $7zr
}

function Expand-Any([string]$archive, [string]$dest) {
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force $dest | Out-Null
    if ($archive -like '*.zip') {
        & tar.exe -xf $archive -C $dest
    } else {
        & (Get-7z) x -y "-o$dest" $archive | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw (Say "falha ao extrair $archive" "failed to extract $archive") }
}

$failed = @()
foreach ($key in $emus.Keys) {
    if ($Only -and $key -notin $Only) { continue }
    $e = $emus[$key]
    Write-Host ''
    Write-Host "== $($e.name)" -ForegroundColor Cyan
    try {
        if ($e.tag) { $relUrl = "https://api.github.com/repos/$($e.repo)/releases/tags/$($e.tag)" }
        else { $relUrl = "https://api.github.com/repos/$($e.repo)/releases/latest" }
        $rel = Invoke-RestMethod $relUrl -Headers @{ 'User-Agent' = 'TriviumHub' }
        $asset = $rel.assets | Where-Object { $_.name -match $e.asset } | Select-Object -First 1
        if (-not $asset) { throw (Say "arquivo para Windows nao encontrado na versao $($rel.tag_name)" "Windows file not found in version $($rel.tag_name)") }

        $dest = Join-Path $EmuDir $key
        $verFile = Join-Path $dest '.versao'
        if ($e.into) { $dest = Join-Path $EmuDir $e.into; $verFile = Join-Path $dest ".versao-$key" }
        if (-not $Force -and (Test-Path $verFile) -and ((Get-Content $verFile -Raw).Trim() -eq $rel.tag_name)) {
            if ($e.tag) { Write-Host (Say "  versao travada ja instalada ($($rel.tag_name))" "  pinned version already installed ($($rel.tag_name))") -ForegroundColor Green }
            else { Write-Host (Say "  ja esta na versao mais nova ($($rel.tag_name))" "  already on the latest version ($($rel.tag_name))") -ForegroundColor Green }
            continue
        }

        $file = Join-Path $Tmp $asset.name
        Write-Host ((Say "  baixando {0} ({1:N0} MB) de github.com/{2}" "  downloading {0} ({1:N0} MB) from github.com/{2}") -f $asset.name, ($asset.size / 1MB), $e.repo)
        & curl.exe -L --fail --progress-bar -o $file $asset.browser_download_url
        if ($LASTEXITCODE -ne 0) { throw (Say 'falha no download' 'download failed') }

        # confere o SHA-256 quando o projeto publica o arquivo .sha256
        $shaAsset = $rel.assets | Where-Object { $_.name -eq "$($asset.name).sha256" } | Select-Object -First 1
        if ($shaAsset) {
            $expected = ((Invoke-RestMethod $shaAsset.browser_download_url -Headers @{ 'User-Agent' = 'TriviumHub' }) -split '\s+')[0].Trim().ToLower()
            $actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
            if ($expected -ne $actual) { throw (Say 'SHA-256 nao confere, download corrompido' 'SHA-256 does not match, corrupted download') }
            Write-Host (Say '  SHA-256 conferido' '  SHA-256 verified') -ForegroundColor Green
        }

        if ($asset.name -like '*.exe') {
            # programa de um arquivo so: copia direto
            New-Item -ItemType Directory -Force $dest | Out-Null
            Copy-Item -LiteralPath $file (Join-Path $dest $e.exe) -Force
            Set-Content -LiteralPath $verFile $rel.tag_name
            Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
            Write-Host (Say "  instalado: $($rel.tag_name)" "  installed: $($rel.tag_name)") -ForegroundColor Green
            continue
        }

        Write-Host (Say '  extraindo...' '  extracting...')
        $x = Join-Path $Tmp "x_$key"
        Expand-Any $file $x
        # se o arquivo tem uma unica pasta dentro, usa o conteudo dela
        $src = $x
        $items = @(Get-ChildItem -LiteralPath $x -Force)
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $src = $items[0].FullName }

        # copia por cima, mantendo saves, configs e jogos instalados (dev_hdd0 etc.)
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force

        $exe = Get-ChildItem -LiteralPath $dest -Recurse -Filter $e.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $exe) { throw (Say "$($e.exe) nao encontrado apos extrair" "$($e.exe) not found after extracting") }
        switch ($key) {
            'pcsx2' { Set-Content -LiteralPath (Join-Path $exe.DirectoryName 'portable.ini') '' }   # modo portatil: configs ficam na pasta
            'shadps4' { New-Item -ItemType Directory -Force (Join-Path $exe.DirectoryName 'user') | Out-Null }
        }
        Set-Content -LiteralPath $verFile $rel.tag_name
        Remove-Item -Recurse -Force $x, $file -ErrorAction SilentlyContinue
        Write-Host (Say "  instalado: $($rel.tag_name)" "  installed: $($rel.tag_name)") -ForegroundColor Green
    } catch {
        Write-Host (Say "  ERRO: $($_.Exception.Message)" "  ERROR: $($_.Exception.Message)") -ForegroundColor Red
        $failed += $e.name
    }
}

# patches da comunidade para jogos de PS4 (repositorio oficial do shadPS4), usados para pular videos/intros
if (-not $Only -or 'shadps4' -in $Only -or 'patches' -in $Only) {
    Write-Host ''
    Write-Host (Say '== Patches de PS4 (shadps4-emu/ps4_cheats)' '== PS4 patches (shadps4-emu/ps4_cheats)') -ForegroundColor Cyan
    try {
        $list = Invoke-RestMethod 'https://api.github.com/repos/shadps4-emu/ps4_cheats/contents/PATCHES' -Headers @{ 'User-Agent' = 'TriviumHub' }
        $pdir = Join-Path $Root 'patches-ps4'
        $ptmp = Join-Path $Tmp 'patches-ps4'
        if (Test-Path $ptmp) { Remove-Item -Recurse -Force $ptmp }
        New-Item -ItemType Directory -Force $ptmp | Out-Null
        $index = [ordered]@{}
        foreach ($f in $list | Where-Object { $_.name -match '\.xml$' }) {
            $dst = Join-Path $ptmp $f.name
            & curl.exe -sL --fail -o $dst $f.download_url
            if ($LASTEXITCODE -ne 0) { throw (Say "falha ao baixar $($f.name)" "failed to download $($f.name)") }
            try { $ids = @(([xml](Get-Content -LiteralPath $dst -Raw -Encoding UTF8)).Patch.TitleID.ID) } catch { continue }
            $index[$f.name] = @($ids | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        }
        # files.json: indice que o shadPS4 usa para achar o arquivo de cada jogo
        [IO.File]::WriteAllText((Join-Path $ptmp 'files.json'), ($index | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path $pdir) { Remove-Item -Recurse -Force $pdir }
        Move-Item $ptmp $pdir
        Write-Host (Say "  $($index.Count) jogos com patches" "  $($index.Count) games with patches") -ForegroundColor Green
    } catch {
        Write-Host (Say "  ERRO: $($_.Exception.Message)" "  ERROR: $($_.Exception.Message)") -ForegroundColor Red
        $failed += (Say 'Patches de PS4' 'PS4 patches')
    }
}

Write-Host ''
if ($failed.Count) { Write-Host (Say "Falharam: $($failed -join ', ')" "Failed: $($failed -join ', ')") -ForegroundColor Red }
else { Write-Host (Say 'Tudo pronto!' 'All done!') -ForegroundColor Green }
if (-not $env:PLAYLAUNCHER_NOPAUSE) { Write-Host (Say 'Esta janela fecha em 5 segundos...' 'This window closes in 5 seconds...'); Start-Sleep 5 }
if ($failed.Count) { exit 1 }
