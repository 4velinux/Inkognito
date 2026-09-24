<#
  Inkognito · smart installer and launcher for Windows
  A locally launched, privacy-first LinkedIn formatter for self-hosting.

    irm https://raw.githubusercontent.com/4velinux/Inkognito/main/install.ps1 | iex

  It looks at the machine and picks the setup on its own:
    Windows 10 / 11 desktop  → for you only: %LOCALAPPDATA%\Inkognito, Start menu entry,
                               http://localhost:8765, opens your browser. No admin needed.
    Windows Server, Server Core,
    or a remote SSH session  → always-on service for your network: %ProgramData%\Inkognito,
                               startup task, firewall rule for private networks. Needs admin.
  Override the guess with -Desktop or -Server.

  Later, from the Start menu or PowerShell:
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1"     (or %ProgramData% for a server install)
      -Stop · -Update · -Status · -Uninstall · -Autostart on|off
  Options: -Port 9000 · -Lan · -NoBrowser · -Yes · -Serve (foreground) · -Detect

  Privacy: launching never touches the network. Only install and -Update download
  the app, from GitHub releases, verified by SHA-256.
#>
[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Stop,
  [switch]$Update,
  [switch]$Status,
  [switch]$Uninstall,
  [switch]$Serve,
  [switch]$Detect,
  [ValidateSet('', 'on', 'off')][string]$Autostart = '',
  [switch]$Desktop,
  [switch]$Server,
  [switch]$Lan,
  [switch]$Yes,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$LauncherVersion = '1.2.0'
$Repo = if ($env:INKOGNITO_REPO) { $env:INKOGNITO_REPO } else { '4velinux/Inkognito' }
$Ref = if ($env:INKOGNITO_REF) { $env:INKOGNITO_REF } else { 'main' }
$Raw = "https://raw.githubusercontent.com/$Repo/$Ref"
$Rel = "https://github.com/$Repo/releases/latest/download"
$DefaultPort = 8765
$TaskName = 'Inkognito'
$FwName = 'Inkognito (private networks)'
if ($Port -eq 0 -and $env:INKOGNITO_PORT) { $Port = [int]$env:INKOGNITO_PORT }
if ($env:INKOGNITO_YES) { $Yes = $true }

$OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$HostExe = (Get-Process -Id $PID).Path
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Say($t) { Write-Host " > $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host " + $t" -ForegroundColor Green }
function Warn($t) { Write-Host " ! $t" -ForegroundColor Yellow }
function Fail($t) {
  Write-Host " x $t" -ForegroundColor Red
  # exit would close the window when run through 'irm | iex', so throw instead
  if ($PSCommandPath) { exit 1 } else { throw 'Inkognito setup stopped.' }
}

# ------------------------------------------------------------------ paths
$UserBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local/share' }
$MachineBase = if ($env:ProgramData) { $env:ProgramData } else { Join-Path ([IO.Path]::GetTempPath()) 'ProgramData' }
function Set-Paths($dir) {
  $script:AppDir = $dir
  $script:Www = Join-Path $dir 'www'
  $script:AppFile = Join-Path $script:Www 'index.html'
  $script:Self = Join-Path $dir 'inkognito.ps1'
  $script:PortFile = Join-Path $dir 'port'
  $script:PidFile = Join-Path $dir 'server.pid'
  $script:ProfileFile = Join-Path $dir 'profile'
  $script:BindFile = Join-Path $dir 'bind'
}
$UserDir = Join-Path $UserBase 'Inkognito'
$MachineDir = Join-Path $MachineBase 'Inkognito'
if ($env:INKOGNITO_HOME) { Set-Paths $env:INKOGNITO_HOME }
elseif (Test-Path (Join-Path $UserDir 'www\index.html')) { Set-Paths $UserDir }
elseif (Test-Path (Join-Path $MachineDir 'www\index.html')) { Set-Paths $MachineDir }
else { Set-Paths $UserDir }

$StartMenu = if ($env:APPDATA) { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' } else { $null }
$MenuLink = if ($StartMenu) { Join-Path $StartMenu 'Inkognito.lnk' } else { $null }
$StartupLink = if ($StartMenu) { Join-Path $StartMenu 'Startup\Inkognito.lnk' } else { $null }

function Read-Saved($file) { if (Test-Path $file) { return (Get-Content $file -Raw).Trim() } else { return '' } }

# ------------------------------------------------------------------ detection
function Test-Admin {
  if (-not $OnWindows) { return $false }
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-HostInfo {
  $info = @{ Name = 'PowerShell on ' + [Environment]::OSVersion.VersionString; ServerOS = $false; Core = $false; Ssh = $false }
  if ($OnWindows) {
    try {
      $os = Get-CimInstance Win32_OperatingSystem
      $info.Name = $os.Caption.Trim()
      $info.ServerOS = ($os.ProductType -ne 1)
    } catch {}
    $info.Core = -not (Test-Path (Join-Path $env:SystemRoot 'explorer.exe'))
  }
  $info.Ssh = [bool]($env:SSH_CLIENT -or $env:SSH_CONNECTION)
  return $info
}
function Get-Profile {
  if ($Server) { return @('server', 'chosen with -Server') }
  if ($Desktop) { return @('desktop', 'chosen with -Desktop') }
  $h = Get-HostInfo
  if ($h.Core) { return @('server', 'Server Core has no desktop, so it will serve your network') }
  if ($h.Ssh) { return @('server', 'you are connected over SSH, so it will serve your network') }
  if ($h.ServerOS) { return @('server', 'Windows Server, so it will serve your network') }
  return @('desktop', 'desktop with a screen')
}

function Get-LanIp {
  try {
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
      Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -in 'Dhcp', 'Manual' } |
      Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip) { return $ip }
  } catch {}
  return $env:COMPUTERNAME
}

# ------------------------------------------------------------------ helpers
function Get-AppVersion($file) {
  if (-not (Test-Path $file)) { return '' }
  $m = Select-String -Path $file -Pattern "var VERSION='([^']+)'" | Select-Object -First 1
  if ($m) { return $m.Matches[0].Groups[1].Value } else { return '' }
}
function Get-Sha($file) { (Get-FileHash -Algorithm SHA256 -Path $file).Hash.ToLower() }
function Download($url, $dest) { Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 90 }
function Test-PortOpen([int]$p) {
  $c = New-Object Net.Sockets.TcpClient
  try { $a = $c.BeginConnect('127.0.0.1', $p, $null, $null); return ($a.AsyncWaitHandle.WaitOne(300) -and $c.Connected) }
  catch { return $false } finally { $c.Close() }
}
function Test-Ours([int]$p) {
  if (-not (Test-PortOpen $p)) { return $false }
  try { $r = Invoke-WebRequest -Uri "http://localhost:$p/" -UseBasicParsing -TimeoutSec 3; return ($r.Content -match '<title>Inkognito</title>') }
  catch { return $false }
}
function Select-Port {
  $p = $Port
  if ($p -eq 0) { $s = Read-Saved $PortFile; if ($s) { $p = [int]$s } }
  if ($p -eq 0) { $p = $DefaultPort }
  if ((Test-PortOpen $p) -and -not (Test-Ours $p)) {
    if ($Port -ne 0) { Fail "Port $p is used by another program. Pick another with -Port." }
    $q = $p + 1; while (Test-PortOpen $q) { $q++ }
    Warn "Port $p is busy, using $q. Drafts are saved per address, so drafts from :$p will not show on :$q."
    $p = $q
  }
  return $p
}
function Wait-Up([int]$p) { for ($i = 0; $i -lt 60 -and -not (Test-PortOpen $p); $i++) { Start-Sleep -Milliseconds 100 }; return (Test-PortOpen $p) }
function Start-Countdown($note) {
  if ($Yes) { return }
  try { if ([Console]::IsInputRedirected) { return } } catch { return }
  Write-Host ''; Write-Host " $note" -ForegroundColor DarkGray
  Write-Host ' Starting in 5 s. Enter starts now, Ctrl+C cancels. ' -NoNewline
  for ($i = 0; $i -lt 50; $i++) {
    try { if ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true); if ($k.Key -eq 'Enter') { break } } } catch { break }
    Start-Sleep -Milliseconds 100
  }
  Write-Host ''
}

function Install-App {
  New-Item -ItemType Directory -Force -Path $Www | Out-Null
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("inkognito-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $new = Join-Path $tmp 'app.html'
  try {
    $src = $env:INKOGNITO_FILE
    if (-not $src -and $PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'inkognito.html'))) { $src = Join-Path $PSScriptRoot 'inkognito.html' }
    if ($src) {
      Say "Using the app from $src"; Copy-Item $src $new
    } else {
      Say "Downloading the latest release of $Repo"
      $gotRelease = $true
      try { Download "$Rel/inkognito.html" $new } catch { $gotRelease = $false }
      if ($gotRelease) {
        $sumFile = Join-Path $tmp 'app.sha256'
        try { Download "$Rel/inkognito.html.sha256" $sumFile } catch { Fail 'The release has no checksum file.' }
        $expected = ((Get-Content $sumFile -Raw).Trim() -split '\s+')[0].ToLower()
        if ($expected -ne (Get-Sha $new)) { Fail 'Checksum mismatch. Nothing was installed.' }
        Ok 'Checksum verified'
      } else {
        Warn 'No release yet, using the main branch (no checksum available).'
        try { Download "$Raw/inkognito.html" $new } catch { Fail 'Download failed. Are you online?' }
      }
    }
    $text = [IO.File]::ReadAllText($new)
    if ($text -notmatch '<title>Inkognito</title>') { Fail 'Downloaded file is not Inkognito.' }
    if ($text -notmatch "connect-src 'none'") { Fail 'Refusing a build without the privacy lock.' }
    if ((Test-Path $AppFile) -and ((Get-Sha $AppFile) -eq (Get-Sha $new))) {
      Ok ("Already on v" + (Get-AppVersion $AppFile))
    } else {
      if (Test-Path $AppFile) { Copy-Item $AppFile (Join-Path $AppDir 'previous.html') -Force }
      Copy-Item $new $AppFile -Force
      Ok ("Installed Inkognito v" + (Get-AppVersion $AppFile))
    }
    Set-Content -Path (Join-Path $Www 'version.txt') -Value ("v" + (Get-AppVersion $AppFile)) -Encoding ASCII
  } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}

function PsArgs($extra) { "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`" $extra".Trim() }
function New-Shortcut($path, $extra) {
  if (-not $OnWindows -or -not $path) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut($path)
  $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $lnk.Arguments = PsArgs $extra
  $lnk.WorkingDirectory = $AppDir
  $lnk.Description = 'Inkognito, privacy-first LinkedIn formatter'
  $lnk.IconLocation = (Join-Path $env:SystemRoot 'System32\imageres.dll') + ',76'
  $lnk.Save()
}

function Install-Self($withMenu) {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  if ($PSCommandPath -and ($PSCommandPath -ne $Self)) { Copy-Item $PSCommandPath $Self -Force }
  elseif (-not (Test-Path $Self) -or $Update) { Download "$Raw/install.ps1" $Self }
  if ($withMenu) { New-Shortcut $MenuLink '' }
}

# ------------------------------------------------------------------ serving
function Start-Server([int]$p) {
  if (Test-Ours $p) { Ok "Already running on port $p"; return }
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Self`"", '-Serve', '-Port', "$p")
  if ($OnWindows) { $proc = Start-Process -FilePath $HostExe -ArgumentList $argList -WindowStyle Hidden -PassThru }
  else { $proc = Start-Process -FilePath $HostExe -ArgumentList $argList -PassThru -RedirectStandardOutput (Join-Path $AppDir 'server.log') -RedirectStandardError (Join-Path $AppDir 'server.err') }
  Set-Content -Path $PidFile -Value $proc.Id -Encoding ASCII
  if (-not (Wait-Up $p)) { Fail 'The server did not start. Try: inkognito.ps1 -Serve to see the error.' }
  Set-Content -Path $PortFile -Value $p -Encoding ASCII
  Ok "Serving on port $p (pid $($proc.Id))"
}

function Invoke-Serve([int]$p) {
  if (-not (Test-Path $AppFile)) { Fail 'App not installed yet. Run without -Serve first.' }
  $headers = [ordered]@{
    'Cache-Control'              = 'no-cache'
    'X-Content-Type-Options'     = 'nosniff'
    'X-Frame-Options'            = 'DENY'
    'Referrer-Policy'            = 'no-referrer'
    'Cross-Origin-Opener-Policy' = 'same-origin'
    'Permissions-Policy'         = 'camera=(), microphone=(), geolocation=(), payment=(), usb=()'
    'Content-Security-Policy'    = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'"
  }
  $wide = $Lan -or ((Read-Saved $BindFile) -eq 'lan')
  $listener = New-Object Net.HttpListener
  if ($wide) { $listener.Prefixes.Add("http://+:$p/") } else { $listener.Prefixes.Add("http://localhost:$p/") }
  try { $listener.Start() } catch { Fail "Could not listen on port ${p}: $($_.Exception.Message)" }
  Write-Host "Inkognito serving on port $p$(if ($wide) { ' for your network' } else { ' for this computer' }) (Ctrl+C to stop)"
  try {
    while ($listener.IsListening) {
      $task = $listener.GetContextAsync()
      while (-not $task.Wait(500)) { }
      $ctx = $task.Result; $res = $ctx.Response
      try {
        $path = $ctx.Request.Url.AbsolutePath
        if ($path -eq '/' -or $path -eq '/index.html') { $bytes = [IO.File]::ReadAllBytes($AppFile); $res.ContentType = 'text/html; charset=utf-8' }
        elseif ($path -eq '/version.txt') { $bytes = [IO.File]::ReadAllBytes((Join-Path $Www 'version.txt')); $res.ContentType = 'text/plain; charset=utf-8' }
        else { $res.StatusCode = 404; $bytes = [Text.Encoding]::UTF8.GetBytes('Not found'); $res.ContentType = 'text/plain; charset=utf-8' }
        foreach ($k in $headers.Keys) { $res.AddHeader($k, $headers[$k]) }
        $res.ContentLength64 = $bytes.Length
        if ($ctx.Request.HttpMethod -ne 'HEAD') { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
      } catch { $res.StatusCode = 500 } finally { $res.Close() }
    }
  } finally { $listener.Stop(); $listener.Close() }
}

# ------------------------------------------------------------------ server profile (admin)
function Install-ServerService([int]$p) {
  # let a non-admin account listen on all interfaces for this port
  & netsh http delete urlacl url="http://+:$p/" 2>$null | Out-Null
  & netsh http add urlacl url="http://+:$p/" user="NT AUTHORITY\LOCAL SERVICE" | Out-Null
  Get-NetFirewallRule -DisplayName $FwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -DisplayName $FwName -Direction Inbound -Protocol TCP -LocalPort $p -Action Allow -Profile Private, Domain | Out-Null
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $action = New-ScheduledTaskAction -Execute $ps -Argument (PsArgs "-Serve -Port $p")
  $trigger = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE' -LogonType ServiceAccount
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Inkognito, privacy-first LinkedIn formatter' -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  if (-not (Wait-Up $p)) { Fail 'The service did not start. Check Task Scheduler > Inkognito.' }
  Ok 'Runs at startup as a low-privilege service, even when nobody is signed in'
}
function Remove-ServerService {
  if (-not $OnWindows) { return }
  $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($t) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
  Get-NetFirewallRule -DisplayName $FwName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  $p = Read-Saved $PortFile
  if ($p) { & netsh http delete urlacl url="http://+:$p/" 2>$null | Out-Null }
}

# ------------------------------------------------------------------ commands
function Stop-Server {
  $stopped = $false
  if ((Read-Saved $ProfileFile) -eq 'server' -and $OnWindows -and (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue; $stopped = $true
  }
  if (Test-Path $PidFile) {
    $id = [int](Get-Content $PidFile -Raw)
    if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Stop-Process -Id $id -Force; $stopped = $true }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  }
  if ($OnWindows) {
    Get-CimInstance Win32_Process -Filter "Name like 'powershell%' or Name like 'pwsh%'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match 'inkognito\.ps1' -and $_.CommandLine -match '-Serve' -and $_.ProcessId -ne $PID } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $stopped = $true }
  }
  if ($stopped) { Ok 'Stopped' } else { Say 'Not running.' }
  if ((Read-Saved $ProfileFile) -eq 'server') { Say 'It starts again with Windows. To stop that: -Autostart off' }
  elseif ($StartupLink -and (Test-Path $StartupLink)) { Warn 'Autostart is on, so it starts again when you sign in. Turn off with -Autostart off.' }
}

function Set-Autostart($state) {
  if (-not $OnWindows) { Fail 'On Linux and macOS use install.sh --autostart.' }
  $p = Read-Saved $PortFile; if (-not $p) { $p = $DefaultPort }
  if ((Read-Saved $ProfileFile) -eq 'server') {
    if (-not (Test-Admin)) { Fail 'Run PowerShell as administrator to change the service.' }
    if ($state -eq 'on') { Install-ServerService ([int]$p) } else { Remove-ServerService; Ok 'Service removed. Start it by hand with inkognito.ps1' }
    return
  }
  if ($state -eq 'on') { New-Shortcut $StartupLink "-Serve -Port $p"; Ok "Starts when you sign in, on http://localhost:$p" }
  else { Remove-Item $StartupLink -Force -ErrorAction SilentlyContinue; Ok 'Autostart off' }
}

function Show-Status {
  $p = Read-Saved $PortFile; if (-not $p) { $p = $DefaultPort }
  $prof = Read-Saved $ProfileFile
  $v = Get-AppVersion $AppFile
  Write-Host (" Setup      " + $(if ($prof) { $prof } else { 'not installed' }))
  Write-Host (" App        " + $(if ($v) { "v$v in $AppDir" } else { 'not installed' }))
  if ($prof -eq 'server') { Write-Host " Address    http://$(Get-LanIp):$p  (and http://localhost:$p)" }
  else { Write-Host " Address    http://localhost:$p  (this computer only)" }
  Write-Host (" Server     " + $(if (Test-Ours ([int]$p)) { 'running' } else { 'stopped' }))
  $auto = 'off'
  if ($prof -eq 'server' -and $OnWindows -and (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { $auto = 'on (startup task)' }
  elseif ($StartupLink -and (Test-Path $StartupLink)) { $auto = 'on (when you sign in)' }
  Write-Host " Autostart  $auto"
  Write-Host " Launcher   v$LauncherVersion"
}

function Remove-All {
  if ((Read-Saved $ProfileFile) -eq 'server') {
    if (-not (Test-Admin)) { Fail 'Run PowerShell as administrator to remove the service.' }
    Remove-ServerService
  }
  Stop-Server | Out-Null
  foreach ($l in @($MenuLink, $StartupLink)) { if ($l -and (Test-Path $l)) { Remove-Item $l -Force } }
  Remove-Item -Recurse -Force $AppDir -ErrorAction SilentlyContinue
  Ok 'Inkognito removed from this computer.'
  Say 'Drafts live in your browser. To erase them too, open Inkognito first and use Erase all local data.'
}

function Open-Browser($url) {
  if ($NoBrowser) { return }
  if ($OnWindows) { Start-Process $url }
  elseif ($IsMacOS) { & open $url }
  elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) { & xdg-open $url *> $null }
  else { Say "Open $url in a browser." }
}

function Show-Banner {
  Write-Host ''
  Write-Host '  Inkognito  ' -NoNewline -ForegroundColor White
  Write-Host 'privacy-first LinkedIn formatter, your drafts stay on your machine' -ForegroundColor DarkGray
  Write-Host ''
}

# ------------------------------------------------------------------ main
if ($Detect) {
  $h = Get-HostInfo; $d = Get-Profile
  "host=$($h.Name)`nserverOS=$($h.ServerOS)`ncore=$($h.Core)`nssh=$($h.Ssh)`nadmin=$(Test-Admin)`nprofile=$($d[0])`nreason=$($d[1])"
  return
}
if ($Serve) { Invoke-Serve (Select-Port); return }
if ($Stop) { Stop-Server; return }
if ($Status) { Show-Status; return }
if ($Uninstall) { Remove-All; return }
if ($Autostart) { if (-not (Test-Path $AppFile)) { Fail 'Install first: run inkognito.ps1 without options.' }; Set-Autostart $Autostart; return }
if ($Update) {
  Install-Self $false; Install-App
  Say 'Reload the page in your browser to use the new version.'
  return
}

$prof = Read-Saved $ProfileFile
if (-not $prof -or $Server -or $Desktop) {
  $d = Get-Profile; $prof = $d[0]
  Show-Banner
  Ok ("Detected " + (Get-HostInfo).Name + " · " + $d[1])
  if ($prof -eq 'server' -and -not (Test-Admin)) {
    Warn 'Serving your network needs an administrator PowerShell. Installing for this account only instead.'
    Say 'For the network setup: open PowerShell as administrator and run the same line again.'
    $prof = 'desktop'
  }
}

if ($prof -eq 'server') {
  if (-not (Test-Path $AppFile)) {
    if (-not $env:INKOGNITO_HOME) { Set-Paths $MachineDir }
    $p = Select-Port
    Say "Plan: install an always-on service on port $p for your whole network"
    Start-Countdown "Installs to $AppDir, starts with Windows, and opens port $p on private networks only. Drafts stay in each person's browser."
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    Set-Content $ProfileFile 'server' -Encoding ASCII; Set-Content $BindFile 'lan' -Encoding ASCII; Set-Content $PortFile $p -Encoding ASCII
    Install-Self $false; Install-App
    Install-ServerService $p
    Write-Host ''
    Write-Host "  Open       http://$(Get-LanIp):$p  from any device on your network" -ForegroundColor Green
    Write-Host "  Commands   & `"$Self`" -Status | -Update | -Stop | -Uninstall"
    Write-Host '  Away from home? Use Tailscale or WireGuard, never an open router port.'
    Write-Host ''
  } else {
    $p = [int](Read-Saved $PortFile)
    if (Test-Ours $p) { Ok "Running on http://$(Get-LanIp):$p" } else { Warn 'Service not answering. Try: -Autostart on (as administrator)' }
  }
  return
}

# desktop
$first = -not (Test-Path $AppFile)
if ($first) {
  $p = Select-Port
  Say "Plan: install for you only, on http://localhost:$p, and open your browser"
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  Set-Content $ProfileFile 'desktop' -Encoding ASCII
  if ($Lan) { Set-Content $BindFile 'lan' -Encoding ASCII }
  Install-Self $true; Install-App
} elseif (-not (Test-Path $Self)) { Install-Self $true }
$p = Select-Port
Start-Server $p
Open-Browser "http://localhost:$p"
if ($first) {
  Write-Host ''
  Write-Host "  Open       http://localhost:$p" -ForegroundColor Green
  Write-Host '  Next time  Start menu > Inkognito'
  Write-Host "  Commands   & `"$Self`" -Status | -Update | -Stop | -Uninstall"
  Write-Host "  At login   & `"$Self`" -Autostart on"
  Write-Host ''
}
