<#
.SYNOPSIS
  Manejador del protocolo ws-claude:// — al hacer clic en un aviso de Claude, trae Windows Terminal al
  frente y lleva tmux a la pestaña y al panel que lo lanzó.
.DESCRIPTION
  Registrado en HKCU\Software\Classes\ws-claude (sin permisos de administrador) por el parche 31.
  Cualquier página web puede pedir abrir ws-claude://… (el navegador pregunta antes); por eso solo se
  acepta ws-claude://foco/<número> y lo único que se hace es cambiar de ventana y de panel.
  __DISTRO__ y __FOCO__ los reemplaza el instalador.
.PARAMETER Uri
  La URI completa que pasa Windows, p. ej. ws-claude://foco/12
#>
param([string]$Uri)

if ($Uri -notmatch '^ws-claude://foco/(\d{1,6})/?$') { exit 1 }
$n = $Matches[1]

# Primero la ventana (Windows solo deja pasar al frente poco después del clic).
$wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($wt) {
    try {
        Add-Type -Namespace WsClaude -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(System.IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
'@ -ErrorAction Stop
        if ([WsClaude.Win]::IsIconic($wt.MainWindowHandle)) { [void][WsClaude.Win]::ShowWindowAsync($wt.MainWindowHandle, 9) }
        [void][WsClaude.Win]::SetForegroundWindow($wt.MainWindowHandle)
    } catch {
        # Sin Add-Type (p. ej. modo de lenguaje restringido): AppActivate no restaura minimizadas, pero sí enfoca.
        [void](New-Object -ComObject WScript.Shell).AppActivate($wt.Id)
    }
}

& wsl.exe -d '__DISTRO__' -e '__FOCO__' $n
