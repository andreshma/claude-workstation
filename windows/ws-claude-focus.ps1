<#
.SYNOPSIS
  Handler for the ws-claude:// protocol — when you click a Claude notification, it brings Windows Terminal
  to the front and takes tmux to the tab and pane that raised it.
.DESCRIPTION
  Registered in HKCU\Software\Classes\ws-claude (no administrator rights) by patch 31.
  Any web page can ask to open ws-claude://… (the browser asks first); that is why only
  ws-claude://focus/<number> (or the older ws-claude://foco/<number>) is accepted and all it does is switch window and pane.
  __DISTRO__ and __FOCUS__ are replaced by the installer.
.PARAMETER Uri
  The full URI passed by Windows, e.g. ws-claude://focus/12
#>
param([string]$Uri)

if ($Uri -notmatch '^ws-claude://(?:focus|foco)/(\d{1,6})/?$') { exit 1 }
$n = $Matches[1]

# The window first (Windows only allows coming to the front shortly after the click).
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
        # Without Add-Type (e.g. constrained language mode): AppActivate does not restore minimized windows, but it does focus.
        [void](New-Object -ComObject WScript.Shell).AppActivate($wt.Id)
    }
}

& wsl.exe -d '__DISTRO__' -e '__FOCUS__' $n
