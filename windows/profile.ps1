<#
  claude-workstation.ps1 — PowerShell shortcuts for the WSL + tmux + Claude Code workstation.
  Source: windows/profile.ps1 in the claude-workstation kit. Do not edit it in the profile
  folder: change it in the kit and run windows/install.ps1 again.
#>

function dev {
  <# .SYNOPSIS Attaches to the tmux session "dev"; if it does not exist, creates it and continuum restores the tabs. #>
  wsl.exe -d Ubuntu -- env LANG=C.UTF-8 tmux -u new -As dev
}

function devo {
  <# .SYNOPSIS Opens a repo from $REPOS or ~/code in a new tab with Claude (needs the dev session open). #>
  param([Parameter(Mandatory)][string]$Repo)
  wsl.exe -d Ubuntu -e bash -lic 'd=$REPOS/$1; [ -d $d ] || d=~/code/$1; tw $d' _ $Repo
}

function devdash {
  <# .SYNOPSIS Dashboard of all tabs: Claude status, model, context, cost and branch. #>
  wsl.exe -d Ubuntu -e bash -lic tmux-dash
}

function devagents {
  <# .SYNOPSIS Live subagents of all tabs: type, what they are doing and the last ones that finished. #>
  wsl.exe -d Ubuntu -e bash -lic tmux-agents
}

function devsave {
  <# .SYNOPSIS Saves the tmux session now (before restarting or shutting down WSL). #>
  wsl.exe -d Ubuntu -- tmux run-shell '~/.tmux/plugins/tmux-resurrect/scripts/save.sh'
}

function devcheck {
  <# .SYNOPSIS Full check: configuration (ws-check) and resilience (ws-health). #>
  wsl.exe -d Ubuntu -e bash -lic 'ws-check; ws-health'
}

function devsnapshot {
  <#
  .SYNOPSIS
    Full backup of the Ubuntu distro as a .vhdx in %UserProfile%\WSL-Backups.
  .DESCRIPTION
    Saves the tmux session and the package list, stops Ubuntu (tmux and the Claude sessions
    close for a few minutes), exports the disk and keeps the $Keep most recent backups.
    Does nothing if C: does not have ~1.2 times the size of the distro disk.
  .PARAMETER Keep
    How many backups to keep (2 by default).
  #>
  param([int]$Keep = 2)
  $dir = Join-Path $env:USERPROFILE 'WSL-Backups'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $base = (Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | Get-ItemProperty |
           Where-Object DistributionName -eq 'Ubuntu').BasePath -replace '^\\\\\?\\', ''
  $sizeGB = (Get-Item (Join-Path $base 'ext4.vhdx')).Length / 1GB
  $freeGB = (Get-PSDrive C).Free / 1GB
  if ($freeGB -lt $sizeGB * 1.2) {
    Write-Error ("C: has {0:N0} GB free and the backup needs ~{1:N0} GB. Free up space first." -f $freeGB, ($sizeGB * 1.2))
    return
  }
  $bk = '/mnt/' + $env:USERPROFILE.Substring(0,1).ToLower() + ($env:USERPROFILE.Substring(2) -replace '\\','/') + '/WSL-Backups'
  wsl.exe -d Ubuntu -e bash -lc "tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh 2>/dev/null; apt-mark showmanual > '$bk/packages.txt'"
  wsl.exe --terminate Ubuntu
  $f = Join-Path $dir ('Ubuntu-{0:yyyyMMdd-HHmm}.vhdx' -f (Get-Date))
  wsl.exe --export Ubuntu $f --vhd
  if ($LASTEXITCODE -ne 0) { Write-Error 'The export failed; no previous backup was deleted.'; return }
  Get-ChildItem $dir -Filter 'Ubuntu-*.vhdx' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $Keep | Remove-Item
  '{0} ({1:N1} GB). Come back in with dev.' -f $f, ((Get-Item $f).Length / 1GB)
}

function devrestoretest {
  <#
  .SYNOPSIS
    Restore test: imports the last snapshot as "Ubuntu-RestoreTest", checks it and deletes it.
  .DESCRIPTION
    Only touches the test distro Ubuntu-RestoreTest; your Ubuntu distro is not modified.
    Needs as much space on C: as the snapshot size while it runs.
  #>
  $f = Get-ChildItem (Join-Path $env:USERPROFILE 'WSL-Backups') -Filter 'Ubuntu-*.vhdx' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { Write-Error 'There are no snapshots; run devsnapshot first.'; return }
  $t = Join-Path $env:USERPROFILE 'WSL-RestoreTest'
  wsl.exe --import Ubuntu-RestoreTest $t $f.FullName --vhd
  if ($LASTEXITCODE -ne 0) { Write-Error 'The import failed.'; return }
  wsl.exe -d Ubuntu-RestoreTest -e bash -lc 'whoami; tmux -V; ls ~/.claude/projects | wc -l; test -f ~/.tmux.conf && echo config-OK'
  wsl.exe --unregister Ubuntu-RestoreTest
  Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
}
