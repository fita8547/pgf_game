@echo off
rem RPS: start the server + tunnel (hidden) now and at every Windows login.
set PS1=%~dp0run-forever.ps1
set LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\RPS server.lnk
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('%LNK%'); $s.TargetPath='powershell.exe'; $s.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%PS1%\"'; $s.WindowStyle=7; $s.Save()"
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS1%"
echo Installed. Link will appear in %~dp0link.txt in ~20 s.
