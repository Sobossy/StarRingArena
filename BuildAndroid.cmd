@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BuildAndroid.ps1" -Install
pause
