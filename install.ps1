<#
  Inkognito · installer and launcher for Windows
  A locally launched, privacy-first LinkedIn formatter for self-hosting.

  One line in PowerShell (no admin needed):
    irm https://raw.githubusercontent.com/4velinux/inkognito/main/install.ps1 | iex

  It installs to %LOCALAPPDATA%\Inkognito, adds "Inkognito" to the Start menu,
  serves the app on http://localhost:8765 (this computer only) and opens your browser.

  Later, from the Start menu or PowerShell:
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1"               start if needed and open
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1" -Stop         stop the local server
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1" -Update       newest release, SHA-256 verified
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1" -Autostart on start when you sign in (off to disable)
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1" -Status
    & "$env:LOCALAPPDATA\Inkognito\inkognito.ps1" -Uninstall
  Options: -Port 9000 · -NoBrowser · -Serve (run in the foreground)

  Privacy: launching never touches the network. Only the first install and
  -Update download the app, from GitHub releases, verified by SHA-256.
#>
[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Stop,
  [switch]$Update,
  [switch]$Status,
  [switch]$Uninstall,
  [switch]$Serve,
  [ValidateSet('', 'on', 'off')][string]$Autostart = '',
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$LauncherVersion = '1.1.0'
$Repo = if ($env:INKOGNITO_REPO) { $env:INKOGNITO_REPO } else { '4velinux/inkognito' }
$Ref = if ($env:INKOGNITO_REF) { $env:INKOGNITO_REF } else { 'main' }
$Raw = "https://raw.githubusercontent.com/$Repo/$Ref"
$Rel = "https://github.com/$Repo/releases/latest/download"
$DefaultPort = 8765
if ($Port -eq 0 -and $env:INKOGNITO_PORT) { $Port = [int]$env:INKOGNITO_PORT }

$OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
$Base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.local/share' }
$AppDir = Join-Path $Base 'Inkognito'
$Www = Join-Path $AppDir 'www'
$AppFile = Join-Path $Www 'index.html'
$Self = Join-Path $AppDir 'inkognito.ps1'
$PortFile = Join-Path $AppDir 'port'
$PidFile = Join-Path $AppDir 'server.pid'
$StartMenu = if ($env:APPDATA) { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs' } else { $null }
$MenuLink = if ($StartMenu) { Join-Path $StartMenu 'Inkognito.lnk' } else { $null }
$StartupLink = if ($StartMenu) { Join-Path $StartMenu 'Startup\Inkognito.lnk' } else { $null }
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
  if ($p -eq 0 -and (Test-Path $PortFile)) { $p = [int](Get-Content $PortFile -Raw) }
  if ($p -eq 0) { $p = $DefaultPort }
  if ((Test-PortOpen $p) -and -not (Test-Ours $p)) {
    if ($Port -ne 0) { Fail "Port $p is used by another program. Pick another with -Port." }
    $q = $p + 1; while (Test-PortOpen $q) { $q++ }
    Warn "Port $p is busy, using $q. Drafts are saved per address, so drafts from :$p will not show on :$q."
    $p = $q
  }
  return $p
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

function New-Shortcut($path, $arguments) {
  if (-not $OnWindows -or -not $path) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut($path)
  $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`" $arguments"
  $lnk.WorkingDirectory = $AppDir
  $lnk.Description = 'Inkognito, privacy-first LinkedIn formatter'
  $lnk.IconLocation = (Join-Path $env:SystemRoot 'System32\imageres.dll') + ',76'
  $lnk.Save()
}

function Install-Self {
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  if ($PSCommandPath -and ($PSCommandPath -ne $Self)) { Copy-Item $PSCommandPath $Self -Force }
  elseif (-not (Test-Path $Self) -or $Update) { Download "$Raw/install.ps1" $Self }
  New-Shortcut $MenuLink ''
}

function Start-Server([int]$p) {
  if (Test-Ours $p) { Ok "Already running on port $p"; return }
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Self`"", '-Serve', '-Port', "$p")
  if ($OnWindows) { $proc = Start-Process -FilePath $HostExe -ArgumentList $argList -WindowStyle Hidden -PassThru }
  else { $proc = Start-Process -FilePath $HostExe -ArgumentList $argList -PassThru -RedirectStandardOutput (Join-Path $AppDir 'server.log') -RedirectStandardError (Join-Path $AppDir 'server.err') }
  Set-Content -Path $PidFile -Value $proc.Id -Encoding ASCII
  for ($i = 0; $i -lt 50 -and -not (Test-PortOpen $p); $i++) { Start-Sleep -Milliseconds 100 }
  if (-not (Test-PortOpen $p)) { Fail 'The server did not start. Try: inkognito.ps1 -Serve to see the error.' }
  Set-Content -Path $PortFile -Value $p -Encoding ASCII
  Ok "Serving on http://localhost:$p (pid $($proc.Id))"
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
  $listener = New-Object Net.HttpListener
  $listener.Prefixes.Add("http://localhost:$p/")
  try { $listener.Start() } catch { Fail "Could not listen on port ${p}: $($_.Exception.Message)" }
  Write-Host "Inkognito serving on http://localhost:$p (Ctrl+C to stop)"
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

function Stop-Server {
  $stopped = $false
  if (Test-Path $PidFile) {
    $id = [int](Get-Content $PidFile -Raw)
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p) { Stop-Process -Id $id -Force; $stopped = $true }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
  }
  if ($OnWindows) {
    Get-CimInstance Win32_Process -Filter "Name like 'powershell%' or Name like 'pwsh%'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match 'inkognito\.ps1' -and $_.CommandLine -match '-Serve' } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $stopped = $true }
  }
  if ($stopped) { Ok 'Stopped' } else { Say 'Not running.' }
  if ($StartupLink -and (Test-Path $StartupLink)) { Warn 'Autostart is on, so it will start again when you sign in. Turn off with -Autostart off.' }
}

function Set-Autostart($state) {
  if (-not $OnWindows) { Fail 'On Linux and macOS use install.sh --autostart.' }
  $p = if (Test-Path $PortFile) { [int](Get-Content $PortFile -Raw) } else { $DefaultPort }
  if ($state -eq 'on') { New-Shortcut $StartupLink "-Serve -Port $p"; Ok "Starts when you sign in, on http://localhost:$p" }
  else { Remove-Item $StartupLink -Force -ErrorAction SilentlyContinue; Ok 'Autostart off' }
}

function Show-Status {
  $p = if (Test-Path $PortFile) { [int](Get-Content $PortFile -Raw) } else { $DefaultPort }
  $v = Get-AppVersion $AppFile
  Write-Host (" App        " + $(if ($v) { "v$v in $AppDir" } else { 'not installed' }))
  Write-Host " Address    http://localhost:$p"
  Write-Host (" Server     " + $(if (Test-Ours $p) { 'running' } else { 'stopped' }))
  Write-Host (" Autostart  " + $(if ($StartupLink -and (Test-Path $StartupLink)) { 'on' } else { 'off' }))
  Write-Host " Launcher   v$LauncherVersion"
}

function Remove-All {
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

# --- main ----------------------------------------------------------------------
if ($Serve) { Invoke-Serve (Select-Port); return }
if ($Stop) { Stop-Server; return }
if ($Status) { Show-Status; return }
if ($Uninstall) { Remove-All; return }
if ($Autostart) { if (-not (Test-Path $AppFile)) { Install-Self; Install-App }; Set-Autostart $Autostart; return }
if ($Update) {
  Install-Self; Install-App
  $p = if (Test-Path $PortFile) { [int](Get-Content $PortFile -Raw) } else { $DefaultPort }
  if (Test-Ours $p) { Say 'Reload the page in your browser to use the new version.' }
  return
}

$first = -not (Test-Path $AppFile)
if ($first) {
  Write-Host ''
  Write-Host '  Inkognito  ' -NoNewline -ForegroundColor White
  Write-Host 'privacy-first LinkedIn formatter, your drafts stay on this computer' -ForegroundColor DarkGray
  Write-Host ''
  Install-Self; Install-App
} elseif (-not (Test-Path $Self)) { Install-Self }
$p = Select-Port
Start-Server $p
Open-Browser "http://localhost:$p"
if ($first) {
  Write-Host ''
  Write-Host "  Open       http://localhost:$p" -ForegroundColor Green
  Write-Host '  Next time  Start menu > Inkognito'
  Write-Host "  Stop       & `"$Self`" -Stop"
  Write-Host "  At login   & `"$Self`" -Autostart on"
  Write-Host ''
}
