@echo off
:: ==========================================
:: Terminate EC2 on AWS Cloud
:: ==========================================

set "SCRIPT_DIR=%~dp0"

powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File \"%SCRIPT_DIR%\setup\ec2-delete.ps1\"' -Verb RunAs"