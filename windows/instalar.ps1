<#
.SYNOPSIS
  Instala los atajos de la estación en el perfil de PowerShell y corrige el perfil Ubuntu
  de Windows Terminal para que abra tmux con UTF-8.
.DESCRIPTION
  Idempotente. Copia profile.ps1 junto a $PROFILE como claude-workstation.ps1 y lo carga
  con una sola línea; quita las funciones dev* pegadas antes a mano. Respalda $PROFILE y
  el settings.json de Windows Terminal (*.bak.<fecha>) antes de cambiarlos.
#>
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- 1. Perfil de PowerShell ------------------------------------------------
$dir = Split-Path $PROFILE
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'profile.ps1') (Join-Path $dir 'claude-workstation.ps1') -Force
$load = '$cw = Join-Path $PSScriptRoot ''claude-workstation.ps1''; if (Test-Path $cw) { . $cw }'
if (Test-Path $PROFILE) {
  $lines = @(Get-Content $PROFILE)
  if ($lines -match '^function (devsnapshot|devrestoretest)') {
    Write-Warning "Tu perfil tiene devsnapshot/devrestoretest de varias líneas; quítalas a mano de $PROFILE."
  }
  Copy-Item $PROFILE "$PROFILE.bak.$stamp"
  $keep = $lines | Where-Object {
    $_ -notmatch '^function (dev|devo|devdash|devagents|devsave|devcheck) ' -and
    $_ -notmatch '^# --- (Estaci.n WSL \+ tmux \+ Claude|Resiliencia de WSL) ---'
  }
  if (-not ($keep -contains $load)) { $keep = @($keep) + '' + '# --- Estación WSL + tmux + Claude (kit claude-workstation) ---' + $load }
  Set-Content $PROFILE $keep -Encoding utf8
} else {
  Set-Content $PROFILE $load -Encoding utf8
}
"Perfil: $PROFILE -> claude-workstation.ps1"

# --- 2. Windows Terminal: perfil Ubuntu con UTF-8 ---------------------------
$old = 'wsl.exe -d Ubuntu -- tmux new -As dev'
$new = 'wsl.exe -d Ubuntu -- env LANG=C.UTF-8 tmux -u new -As dev'
$wts = @(Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal*\LocalState\settings.json",
                       "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json" -ErrorAction SilentlyContinue)
foreach ($wt in $wts) {
  $txt = [IO.File]::ReadAllText($wt.FullName)
  if ($txt.Contains($new)) { "Windows Terminal: ya estaba corregido ($($wt.FullName))" }
  elseif ($txt.Contains($old)) {
    Copy-Item $wt.FullName "$($wt.FullName).bak.$stamp"
    [IO.File]::WriteAllText($wt.FullName, $txt.Replace($old, $new))
    "Windows Terminal: perfil Ubuntu corregido ($($wt.FullName))"
  } else {
    Write-Warning "No encontré '$old' en $($wt.FullName). Líneas con tmux:"
    Select-String -Path $wt.FullName -Pattern 'tmux' | ForEach-Object { '  ' + $_.Line.Trim() }
  }
}
if (-not $wts) { Write-Warning 'No encontré el settings.json de Windows Terminal.' }
'Listo. Abre una ventana nueva de PowerShell (o corre: . $PROFILE).'
