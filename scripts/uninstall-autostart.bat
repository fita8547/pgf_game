@echo off
rem RPS: remove the login autostart and stop the running server + tunnel.
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\RPS server.lnk" >nul 2>&1
call "%~dp0stop-forever.bat"
