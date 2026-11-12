# RPS: keep the game server AND the Cloudflare quick tunnel running, hidden.
# Restarts either one a few seconds after it stops. Writes the current public
# link to scripts\link.txt (the quick-tunnel link changes on every restart).
# Logs: scripts\logs\server.log, scripts\logs\tunnel.log
# Stop: scripts\stop-forever.bat
param([int]$Port = 8090)

$ErrorActionPreference = 'Continue'
$root    = Split-Path -Parent $PSScriptRoot
$dart    = Join-Path $env:USERPROFILE 'Downloads\flutter\bin\cache\dart-sdk\bin\dart.exe'
$cf      = Join-Path $env:USERPROFILE 'tools\cloudflared.exe'
$logDir  = Join-Path $PSScriptRoot 'logs'
$linkTxt = Join-Path $PSScriptRoot 'link.txt'
New-Item -ItemType Directory -Force $logDir | Out-Null

# Only one supervisor at a time.
$mutex = New-Object System.Threading.Mutex($false, 'Local\RPS-run-forever')
if (-not $mutex.WaitOne(0)) { exit 0 }
Set-Content -Path (Join-Path $logDir 'supervisor.pid') -Value $PID

function Log($file, $msg) {
  Add-Content -Path (Join-Path $logDir $file) -Value ("[{0:yyyy-MM-dd HH:mm:ss}] {1}" -f (Get-Date), $msg)
}

function Start-Server {
  Log 'server.log' "starting server on port $Port"
  Start-Process -FilePath $dart -ArgumentList 'run', 'bin/server.dart', '--port', $Port `
    -WorkingDirectory (Join-Path $root 'server') -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logDir 'server.out.log') `
    -RedirectStandardError  (Join-Path $logDir 'server.err.log')
}

function Start-Tunnel {
  Log 'tunnel.log' 'starting cloudflared quick tunnel'
  Set-Content -Path $linkTxt -Value '(waiting for link...)'
  Start-Process -FilePath $cf -ArgumentList 'tunnel', '--no-autoupdate', '--url', "http://localhost:$Port" `
    -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput (Join-Path $logDir 'tunnel.out.log') `
    -RedirectStandardError  (Join-Path $logDir 'tunnel.err.log')
}

$server = $null; $tunnel = $null; $linkFound = $false
while ($true) {
  if ($null -eq $server -or $server.HasExited) {
    if ($server) { Log 'server.log' "server stopped (exit $($server.ExitCode)), restarting" }
    $server = Start-Server
    Start-Sleep -Seconds 8   # let it bind the port before the tunnel connects
  }
  if (Test-Path $cf) {
    if ($null -eq $tunnel -or $tunnel.HasExited) {
      if ($tunnel) { Log 'tunnel.log' "tunnel stopped (exit $($tunnel.ExitCode)), restarting" }
      $tunnel = Start-Tunnel; $linkFound = $false
    }
    if (-not $linkFound) {
      $m = Select-String -Path (Join-Path $logDir 'tunnel.err.log') -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -ErrorAction SilentlyContinue |
        Select-Object -Last 1
      if ($m) {
        $url = $m.Matches[0].Value
        Set-Content -Path $linkTxt -Value $url
        Log 'tunnel.log' "link: $url"
        $linkFound = $true
      }
    }
  }
  Start-Sleep -Seconds 3
}
