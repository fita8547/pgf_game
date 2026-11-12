@echo off
rem RPS: stop the hidden server + tunnel started by run-forever.ps1.
rem (They start again at the next Windows login; run uninstall-autostart.bat to stop that.)
set PIDFILE=%~dp0logs\supervisor.pid
if not exist "%PIDFILE%" goto children
set /p SUP=<"%PIDFILE%"
taskkill /F /PID %SUP% >nul 2>&1
del "%PIDFILE%"
:children
taskkill /F /IM cloudflared.exe >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R /C:":8090 .*LISTENING"') do taskkill /F /T /PID %%p >nul 2>&1
echo Stopped.
