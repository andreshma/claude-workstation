<#
  claude-workstation.ps1 — atajos de PowerShell para la estación WSL + tmux + Claude Code.
  Fuente: windows/profile.ps1 del kit claude-workstation. No lo edites en la carpeta del
  perfil: cámbialo en el kit y vuelve a correr windows/instalar.ps1.
#>

function dev {
  <# .SYNOPSIS Entra a la sesión tmux "dev"; si no existe la crea y continuum restaura las pestañas. #>
  wsl.exe -d Ubuntu -- env LANG=C.UTF-8 tmux -u new -As dev
}

function devo {
  <# .SYNOPSIS Abre un repo de $REPOS o de ~/code en una pestaña nueva con Claude (requiere la sesión dev abierta). #>
  param([Parameter(Mandatory)][string]$Repo)
  wsl.exe -d Ubuntu -e bash -lic 'd=$REPOS/$1; [ -d $d ] || d=~/code/$1; tw $d' _ $Repo
}

function devdash {
  <# .SYNOPSIS Tablero de todas las pestañas: estado de Claude, modelo, contexto, costo y rama. #>
  wsl.exe -d Ubuntu -e bash -lic tmux-dash
}

function devagents {
  <# .SYNOPSIS Subagentes en vivo de todas las pestañas: tipo, qué hacen y los últimos que terminaron. #>
  wsl.exe -d Ubuntu -e bash -lic tmux-agents
}

function devsave {
  <# .SYNOPSIS Guarda ahora la sesión de tmux (antes de reiniciar o apagar WSL). #>
  wsl.exe -d Ubuntu -- tmux run-shell '~/.tmux/plugins/tmux-resurrect/scripts/save.sh'
}

function devcheck {
  <# .SYNOPSIS Revisión completa: configuración (ws-check) y resiliencia (ws-health). #>
  wsl.exe -d Ubuntu -e bash -lic 'ws-check; ws-health'
}

function devsnapshot {
  <#
  .SYNOPSIS
    Respaldo completo de la distro Ubuntu como .vhdx en %UserProfile%\WSL-Backups.
  .DESCRIPTION
    Guarda la sesión de tmux y la lista de paquetes, detiene Ubuntu (tmux y los Claude se
    cierran unos minutos), exporta el disco y conserva los $Keep respaldos más recientes.
    No hace nada si C: no tiene ~1.2 veces el tamaño del disco de la distro.
  .PARAMETER Keep
    Cuántos respaldos conservar (2 por defecto).
  #>
  param([int]$Keep = 2)
  $dir = Join-Path $env:USERPROFILE 'WSL-Backups'
  New-Item -ItemType Directory -Force $dir | Out-Null
  $base = (Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | Get-ItemProperty |
           Where-Object DistributionName -eq 'Ubuntu').BasePath -replace '^\\\\\?\\', ''
  $sizeGB = (Get-Item (Join-Path $base 'ext4.vhdx')).Length / 1GB
  $freeGB = (Get-PSDrive C).Free / 1GB
  if ($freeGB -lt $sizeGB * 1.2) {
    Write-Error ("C: tiene {0:N0} GB libres y el respaldo necesita ~{1:N0} GB. Libera espacio primero." -f $freeGB, ($sizeGB * 1.2))
    return
  }
  $bk = '/mnt/' + $env:USERPROFILE.Substring(0,1).ToLower() + ($env:USERPROFILE.Substring(2) -replace '\\','/') + '/WSL-Backups'
  wsl.exe -d Ubuntu -e bash -lc "tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh 2>/dev/null; apt-mark showmanual > '$bk/paquetes.txt'"
  wsl.exe --terminate Ubuntu
  $f = Join-Path $dir ('Ubuntu-{0:yyyyMMdd-HHmm}.vhdx' -f (Get-Date))
  wsl.exe --export Ubuntu $f --vhd
  if ($LASTEXITCODE -ne 0) { Write-Error 'La exportación falló; no se borró ningún respaldo anterior.'; return }
  Get-ChildItem $dir -Filter 'Ubuntu-*.vhdx' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $Keep | Remove-Item
  '{0} ({1:N1} GB). Vuelve a entrar con dev.' -f $f, ((Get-Item $f).Length / 1GB)
}

function devrestoretest {
  <#
  .SYNOPSIS
    Prueba de restauración: importa el último snapshot como "Ubuntu-RestoreTest", lo revisa y lo borra.
  .DESCRIPTION
    Solo toca la distro de prueba Ubuntu-RestoreTest; tu distro Ubuntu no se modifica.
    Necesita en C: otro tanto del tamaño del snapshot mientras corre.
  #>
  $f = Get-ChildItem (Join-Path $env:USERPROFILE 'WSL-Backups') -Filter 'Ubuntu-*.vhdx' -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { Write-Error 'No hay snapshots; corre devsnapshot primero.'; return }
  $t = Join-Path $env:USERPROFILE 'WSL-RestoreTest'
  wsl.exe --import Ubuntu-RestoreTest $t $f.FullName --vhd
  if ($LASTEXITCODE -ne 0) { Write-Error 'La importación falló.'; return }
  wsl.exe -d Ubuntu-RestoreTest -e bash -lc 'whoami; tmux -V; ls ~/.claude/projects | wc -l; test -f ~/.tmux.conf && echo config-OK'
  wsl.exe --unregister Ubuntu-RestoreTest
  Remove-Item -Recurse -Force $t -ErrorAction SilentlyContinue
}
