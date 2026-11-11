@echo off
rem RPS: run the game server and restart it whenever it stops (crash, error).
rem Close this window to stop the server for good.
setlocal
set ROOT=%~dp0..
set DART=%USERPROFILE%\Downloads\flutter\bin\cache\dart-sdk\bin\dart.exe
set PORT=8090
if not "%~1"=="" set PORT=%~1
title RPS server :%PORT% (close to stop)
cd /d "%ROOT%\server"

:loop
echo [%date% %time%] starting server on port %PORT%
"%DART%" run bin/server.dart --port %PORT%
echo [%date% %time%] server stopped (exit %errorlevel%), restarting in 3 s...
timeout /t 3 /nobreak >nul
goto loop
