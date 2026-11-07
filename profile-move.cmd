@echo off
rem Profile move window: start.ps1 asks the admin account, then opens the window (PowerShell 5.1, no console)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0start.ps1"
