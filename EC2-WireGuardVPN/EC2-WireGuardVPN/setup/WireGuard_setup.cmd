@echo off
:: ==========================================
:: Launcher for WireGuard Client VPN Installer
:: ==========================================

echo Starting WireGuard Installer...
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0WireGuard.ps1"