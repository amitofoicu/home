Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# ==========================================
# Enterprise WireGuard Local Installer
# Auto Elevate + Install + Config Deploy
# ==========================================

# Check if running as administrator, if not, relaunch as admin
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Not running as administrator. Relaunching with admin privileges..." -ForegroundColor Yellow
    
    # Get the script path
    $scriptPath = $MyInvocation.MyCommand.Path
    
    # Create a process start info object
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $startInfo.Verb = "runas"
    $startInfo.UseShellExecute = $true
    
    try {
        # Start the process with admin privileges
        $process = [System.Diagnostics.Process]::Start($startInfo)
        Write-Host "Elevated process started. Exiting current session..." -ForegroundColor Green
        exit 0
    }
    catch {
        Write-Host "Failed to elevate privileges: $_" -ForegroundColor Red
        Write-Host "Please run the script manually as Administrator." -ForegroundColor Red
        exit 1001
    }
}

# -------- MAIN SCRIPT (RUNNING AS ADMIN) --------
$ErrorActionPreference = "Stop"

# -------- CONFIG --------
# Local files in the same directory as this script
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalMsi64 = Join-Path $ScriptDir "wireguard-amd64-0.5.3.msi"
$LocalMsi32 = Join-Path $ScriptDir "wireguard-x86-0.5.3.msi"
$LocalConfigZip = Join-Path $ScriptDir "wireguard-client2-config.zip"

# Optional: SHA256 hashes
$ExpectedHash64 = ""
$ExpectedHash32 = ""

# ------------------------

function Write-Log {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Exit-WithError {
    param([string]$Message, [int]$Code)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit $Code
}

Write-Host @"

=========================================
    WireGuard Local Installer
    Running with Administrator privileges
=========================================
"@ -ForegroundColor Magenta

# Check if WireGuard is already installed
Write-Log "Checking if WireGuard is installed..."
$Installed = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "WireGuard*" }

if ($Installed) {
    Write-Log "WireGuard already installed. Skipping installation."
}
else {
    Write-Log "Detecting OS architecture..."

    if ([Environment]::Is64BitOperatingSystem) {
        $MsiPath = $LocalMsi64
        $ExpectedHash = $ExpectedHash64
        Write-Log "64-bit detected. Using: $MsiPath"
    }
    else {
        $MsiPath = $LocalMsi32
        $ExpectedHash = $ExpectedHash32
        Write-Log "32-bit detected. Using: $MsiPath"
    }

    # Check if local MSI file exists
    if (-not (Test-Path $MsiPath)) {
        Exit-WithError "Local MSI file not found: $MsiPath" 1002
    }

    if ($ExpectedHash -ne "") {
        Write-Log "Verifying SHA256..."
        $Hash = (Get-FileHash $MsiPath -Algorithm SHA256).Hash
        if ($Hash -ne $ExpectedHash) {
            Exit-WithError "SHA256 mismatch." 1003
        }
    }

    Write-Log "Installing silently..."
    $Process = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList "/i `"$MsiPath`" /qn /norestart" `
        -Wait -PassThru

    if ($Process.ExitCode -ne 0 -and $Process.ExitCode -ne 3010) { # 3010 = restart required
        Exit-WithError "Installation failed: $($Process.ExitCode)" 1004
    }

    if ($Process.ExitCode -eq 3010) {
        Write-Log "Installation completed. Restart may be required." -ForegroundColor Yellow
    } else {
        Write-Log "Installation completed."
    }
}

# --------------------------
# Deploy configuration
# --------------------------

Write-Log "Checking configuration ZIP..."

# Check if local config zip exists
if (-not (Test-Path $LocalConfigZip)) {
    Exit-WithError "Local configuration ZIP not found: $LocalConfigZip" 1005
}

$ExtractPath = Join-Path $env:TEMP "wg-config"

if (Test-Path $ExtractPath) {
    Remove-Item $ExtractPath -Recurse -Force
}

Write-Log "Extracting configuration from local ZIP..."
Expand-Archive -Path $LocalConfigZip -DestinationPath $ExtractPath -Force

# WireGuard config directory
$ConfigTarget = "C:\Program Files\WireGuard\Data\Configurations"

# Try to find config directory in different possible locations
if (-not (Test-Path $ConfigTarget)) {
    $AltConfigTarget = "C:\ProgramData\WireGuard\Configurations"
    if (Test-Path $AltConfigTarget) {
        $ConfigTarget = $AltConfigTarget
        Write-Log "Using alternate config directory: $ConfigTarget"
    }
    else {
        Exit-WithError "WireGuard config directory not found." 1006
    }
}

Write-Log "Deploying configuration files..."

$confFiles = Get-ChildItem -Path $ExtractPath -Filter "*.conf" -Recurse
if ($confFiles.Count -eq 0) {
    Exit-WithError "No .conf files found in the ZIP archive." 1007
}

$confFiles | ForEach-Object {
    $destPath = Join-Path $ConfigTarget $_.Name
    Copy-Item $_.FullName -Destination $destPath -Force
    Write-Log "  Deployed: $($_.Name)"
}

# Clean up temp files
Remove-Item $ExtractPath -Recurse -Force

Write-Log "Configuration deployed successfully."

Write-Host "`n=========================================" -ForegroundColor Magenta
Write-Host "All operations completed successfully!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Magenta

Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit 0