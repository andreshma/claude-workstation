<#
.SYNOPSIS
  Installs the workstation shortcuts in the PowerShell profile and fixes the Ubuntu profile
  of Windows Terminal so it opens tmux with UTF-8.
.DESCRIPTION
  Idempotent. Copies profile.ps1 next to $PROFILE as claude-workstation.ps1 and loads it
  with a single line; removes the dev* functions pasted by hand earlier. Backs up $PROFILE and
  the Windows Terminal settings.json (*.bak.<date>) before changing them.
#>
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- 1. PowerShell profile --------------------------------------------------
$dir = Split-Path $PROFILE
New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'profile.ps1') (Join-Path $dir 'claude-workstation.ps1') -Force
$load = '$cw = Join-Path $PSScriptRoot ''claude-workstation.ps1''; if (Test-Path $cw) { . $cw }'
if (Test-Path $PROFILE) {
  $lines = @(Get-Content $PROFILE)
  if ($lines -match '^function (devsnapshot|devrestoretest)') {
    Write-Warning "Your profile has multi-line devsnapshot/devrestoretest functions; remove them by hand from $PROFILE."
  }
  Copy-Item $PROFILE "$PROFILE.bak.$stamp"
  # Spanish on purpose: the second pattern matches marker lines already written to existing profiles.
  $keep = $lines | Where-Object {
    $_ -notmatch '^function (dev|devo|devdash|devagents|devsave|devcheck) ' -and
    $_ -notmatch '^# --- (Estaci.n WSL \+ tmux \+ Claude|Resiliencia de WSL) ---'
  }
  if (-not ($keep -contains $load)) { $keep = @($keep) + '' + '# --- WSL + tmux + Claude workstation (claude-workstation kit) ---' + $load }
  Set-Content $PROFILE $keep -Encoding utf8
} else {
  Set-Content $PROFILE $load -Encoding utf8
}
"Profile: $PROFILE -> claude-workstation.ps1"

# --- 2. Windows Terminal: Ubuntu profile with UTF-8 -------------------------
$old = 'wsl.exe -d Ubuntu -- tmux new -As dev'
$new = 'wsl.exe -d Ubuntu -- env LANG=C.UTF-8 tmux -u new -As dev'
$wts = @(Get-ChildItem "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal*\LocalState\settings.json",
                       "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json" -ErrorAction SilentlyContinue)
foreach ($wt in $wts) {
  $txt = [IO.File]::ReadAllText($wt.FullName)
  if ($txt.Contains($new)) { "Windows Terminal: already fixed ($($wt.FullName))" }
  elseif ($txt.Contains($old)) {
    Copy-Item $wt.FullName "$($wt.FullName).bak.$stamp"
    [IO.File]::WriteAllText($wt.FullName, $txt.Replace($old, $new))
    "Windows Terminal: Ubuntu profile fixed ($($wt.FullName))"
  } else {
    Write-Warning "Could not find '$old' in $($wt.FullName). Lines with tmux:"
    Select-String -Path $wt.FullName -Pattern 'tmux' | ForEach-Object { '  ' + $_.Line.Trim() }
  }
}
if (-not $wts) { Write-Warning 'Could not find the Windows Terminal settings.json.' }
'Done. Open a new PowerShell window (or run: . $PROFILE).'
