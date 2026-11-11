@echo off
rem RPS: start the game server and open a free Cloudflare quick tunnel so
rem friends can join from anywhere with the https://....trycloudflare.com link.
rem Close both windows to stop. The link changes every time.
setlocal
set ROOT=%~dp0..
set DART=%USERPROFILE%\Downloads\flutter\bin\cache\dart-sdk\bin\dart.exe
set CF=%USERPROFILE%\tools\cloudflared.exe
set PORT=8090

if not exist "%CF%" (
  echo cloudflared.exe not found at %CF%
  echo Download: https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe
  pause
  exit /b 1
)

rem Server (skip if something already listens on the port)
netstat -ano | findstr /R /C:":%PORT% .*LISTENING" >nul
if errorlevel 1 (
  start "RPS server" cmd /k "cd /d "%ROOT%\server" && "%DART%" run bin/server.dart --port %PORT%"
  timeout /t 8 /nobreak >nul
) else (
  echo Server already running on port %PORT%.
)

echo.
echo ==== Copy the https://....trycloudflare.com link below and send it to friends ====
echo.
"%CF%" tunnel --no-autoupdate --url http://localhost:%PORT%
