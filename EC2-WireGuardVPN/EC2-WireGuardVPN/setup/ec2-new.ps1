# ==============================
# KILL RUNNING WIREGUARD PROCESSES
# ==============================
Write-Host "=========================================" -ForegroundColor Yellow
Write-Host "Checking for running WireGuard processes..." -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Yellow

$wireguardProcesses = Get-Process -Name "wireguard" -ErrorAction SilentlyContinue

if ($wireguardProcesses) {
    Write-Host "Found running WireGuard process(es). Terminating..." -ForegroundColor Yellow
    $wireguardProcesses | ForEach-Object {
        Write-Host "  Killing process ID: $($_.Id)" -ForegroundColor Gray
        Stop-Process -Id $_.Id -Force
    }
    Write-Host "All WireGuard processes terminated." -ForegroundColor Green
} else {
    Write-Host "No running WireGuard processes found." -ForegroundColor Green
}

Write-Host ""

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# ==============================
# CONFIG
# ==============================
$AMIId           = "ami-098d7f3f866fca1fd"
$Region          = "ap-southeast-1"
$InstanceType    = "t4g.nano"
$Domain          = "server.local"
$UserDataFile    = "installwg.sh"
$NameTag         = "EC2-WireGuard"

$WireGuardExe    = "C:\Program Files\WireGuard\wireguard.exe"
$WGConfigPath    = "C:\Program Files\WireGuard\Data\Configurations\AWS-Debian.conf.dpapi"

# ==============================
# PAUSE FUNCTION
# ==============================
function Pause-Script {
    Write-Host "`n=========================================" -ForegroundColor Cyan
    Write-Host "Press any key to exit..." -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ==============================
# AWS HELPERS
# ==============================
function Get-InstanceState($InstanceId) {
    aws ec2 describe-instances `
        --instance-ids $InstanceId `
        --region $Region `
        --query "Reservations[].Instances[].State.Name" `
        --output text
}

function Get-RunningInstance {
    aws ec2 describe-instances `
        --filters "Name=instance-state-name,Values=running" "Name=tag:Name,Values=$NameTag" `
        --region $Region `
        --query "Reservations[].Instances[0].[InstanceId,PublicIpAddress]" `
        --output text
}

function Tag-Instance($InstanceId) {
    aws ec2 create-tags `
        --resources $InstanceId `
        --region $Region `
        --tags Key=Name,Value=$NameTag | Out-Null
}

function Update-HostsFile($Domain, $PublicIP) {
    $HostsPath = "C:\Windows\System32\drivers\etc\hosts"
    
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Host "Warning: Not running as Administrator. Cannot update hosts file." -ForegroundColor Yellow
        Write-Host "Please manually add this entry to your hosts file:" -ForegroundColor Yellow
        Write-Host "$PublicIP`t$Domain" -ForegroundColor Cyan
        return
    }
    
    try {
        $content = Get-Content $HostsPath | Where-Object { $_ -notmatch "\s+$Domain$" }
        $content += "$PublicIP`t$Domain"
        Set-Content -Path $HostsPath -Value $content -Force
        Write-Host "Hosts file updated: $Domain -> $PublicIP" -ForegroundColor Green
    } catch {
        Write-Host "Failed to update hosts file: $_" -ForegroundColor Yellow
        Write-Host "Please manually add this entry to your hosts file:" -ForegroundColor Yellow
        Write-Host "$PublicIP`t$Domain" -ForegroundColor Cyan
    }
}

# ==============================
# SECURITY GROUP FUNCTIONS
# ==============================
function Get-SecurityGroup($GroupName) {
    try {
        $groupId = aws ec2 describe-security-groups `
            --group-names $GroupName `
            --region $Region `
            --query "SecurityGroups[0].GroupId" `
            --output text 2>$null
        
        if ($groupId -and $groupId -ne "None" -and $groupId -ne "") {
            return $groupId
        }
    } catch {
        # Group doesn't exist
    }
    return $null
}

function Create-SecurityGroup($GroupName, $Description) {
    Write-Host "Creating security group: $GroupName" -ForegroundColor Yellow
    
    $groupId = aws ec2 create-security-group `
        --group-name $GroupName `
        --description $Description `
        --region $Region `
        --query "GroupId" `
        --output text
    
    Write-Host "Created security group: $groupId" -ForegroundColor Green
    return $groupId
}

function Add-WireGuardRule($GroupId) {
    Write-Host "Adding WireGuard UDP 51820 inbound rule..." -ForegroundColor Yellow
    
    $result = aws ec2 authorize-security-group-ingress `
        --group-id $GroupId `
        --protocol udp `
        --port 51820 `
        --cidr 0.0.0.0/0 `
        --region $Region 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Added UDP 51820 inbound rule from 0.0.0.0/0" -ForegroundColor Green
    } else {
        Write-Host "Rule may already exist or could not be added" -ForegroundColor Gray
    }
}

function Ensure-SecurityGroup {
    $WGGroupName = "wg-security-group"
    $WGGroupDesc = "WireGuard VPN Security Group"
    
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Checking WireGuard security group..." -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $groupId = Get-SecurityGroup -GroupName $WGGroupName
    
    if ($groupId) {
        Write-Host "Found existing security group: $groupId" -ForegroundColor Green
        
        # Check if SSH rule exists and warn about it
        $sshRuleExists = aws ec2 describe-security-groups `
            --group-ids $groupId `
            --region $Region `
            --query "SecurityGroups[0].IpPermissions[?FromPort=='22' && ToPort=='22' && IpProtocol=='tcp']" `
            --output text 2>$null
        
        if ($sshRuleExists -and $sshRuleExists -ne "") {
            Write-Host "WARNING: Security group has SSH port 22 open" -ForegroundColor Yellow
            Write-Host "This instance will be created WITHOUT a key pair, so SSH access will not be possible anyway." -ForegroundColor Yellow
        }
    } else {
        $groupId = Create-SecurityGroup -GroupName $WGGroupName -Description $WGGroupDesc
        Add-WireGuardRule -GroupId $groupId
        # SSH rule intentionally NOT added for keyless instances
        Write-Host "NOTE: SSH rule not added (no key pair will be used)" -ForegroundColor Yellow
    }
    
    return $groupId
}

# ==============================
# WIREGUARD FUNCTIONS
# ==============================
function Connect-WireGuard {
    if (-not (Test-Path $WGConfigPath)) {
        throw "WireGuard config not found at: $WGConfigPath"
    }

    Write-Host "Starting WireGuard tunnel service..." -ForegroundColor Cyan
    & $WireGuardExe /installtunnelservice $WGConfigPath | Out-Null
    Write-Host "WireGuard tunnel service installed" -ForegroundColor Green
}

# ==============================
# GET SCRIPT DIRECTORY
# ==============================
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$UserDataFullPath = Join-Path -Path $scriptDirectory -ChildPath $UserDataFile

Write-Host "Script directory: $scriptDirectory" -ForegroundColor Gray
Write-Host "User data path: $UserDataFullPath" -ForegroundColor Gray
Write-Host ""

# ==============================
# MAIN
# ==============================
try {
    Write-Host "=========================================" -ForegroundColor Magenta
    Write-Host "AWS EC2 WireGuard Launcher (No Key Pair)" -ForegroundColor Magenta
    Write-Host "=========================================" -ForegroundColor Magenta
    Write-Host ""

    # Ensure security group exists
    $SecurityGroupId = Ensure-SecurityGroup
    
    Write-Host "Using security group: $SecurityGroupId" -ForegroundColor Cyan
    Write-Host "Key Pair: None (SSH access disabled)" -ForegroundColor Yellow
    Write-Host ""

    $instanceInfo = Get-RunningInstance

    if ($instanceInfo) {
        $InstanceId, $PublicIP = $instanceInfo.Split("`t")

        Write-Host "Found running instance:" -ForegroundColor Green
        Write-Host "  Instance ID: $InstanceId" -ForegroundColor White
        Write-Host "  Public IP: $PublicIP" -ForegroundColor White
        Write-Host "  Domain: $Domain" -ForegroundColor White
        Write-Host "  Key Pair: None" -ForegroundColor Yellow
        Write-Host ""
        
        Tag-Instance $InstanceId
        Update-HostsFile $Domain $PublicIP
        
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "Setting up WireGuard connection..." -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""

        Connect-WireGuard
        
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Magenta
        Write-Host "WireGuard tunnel service installed" -ForegroundColor Green
        Write-Host "VPN should be operational" -ForegroundColor Green
        Write-Host "You can now access: $Domain" -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT: SSH access is disabled (no key pair)" -ForegroundColor Yellow
        Write-Host "=========================================" -ForegroundColor Magenta

    } else {
        Write-Host "Launching new EC2 instance..." -ForegroundColor Cyan
        Write-Host "  AMI: $AMIId" -ForegroundColor Gray
        Write-Host "  Type: $InstanceType" -ForegroundColor Gray
        Write-Host "  Region: $Region" -ForegroundColor Gray
        Write-Host "  Security Group: $SecurityGroupId" -ForegroundColor Gray
        Write-Host "  Key Pair: None (SSH access disabled)" -ForegroundColor Yellow
        Write-Host "  UserData: $UserDataFullPath" -ForegroundColor Gray
        Write-Host ""

        if (-not (Test-Path $UserDataFullPath)) {
            throw "User data file not found at: $UserDataFullPath"
        }
        
        # Remove --key-name parameter to create instance without key pair
        $InstanceId = aws ec2 run-instances `
            --image-id $AMIId `
            --instance-type $InstanceType `
            --security-group-ids $SecurityGroupId `
            --count 1 `
            --region $Region `
            --user-data fileb://$UserDataFullPath `
            --query "Instances[0].InstanceId" `
            --output text

        if (-not $InstanceId -or $InstanceId -eq "") {
            throw "Failed to create instance. No InstanceId returned."
        }

        Write-Host "Instance created: $InstanceId" -ForegroundColor Green

        Write-Host "Waiting for instance to enter running state..." -ForegroundColor Yellow
        do {
            Start-Sleep 2
            $state = Get-InstanceState $InstanceId
            Write-Host "  State: $state" -ForegroundColor Gray
            
            if ($state -eq "terminated" -or $state -eq "shutting-down") {
                throw "Instance entered $state state. Check AWS console for details."
            }
        } while ($state -ne "running")

        Write-Host "Instance is running!" -ForegroundColor Green
        Tag-Instance $InstanceId

        $PublicIP = aws ec2 describe-instances `
            --instance-ids $InstanceId `
            --region $Region `
            --query "Reservations[].Instances[].PublicIpAddress" `
            --output text

        Write-Host "Public IP: $PublicIP" -ForegroundColor Green
        Update-HostsFile $Domain $PublicIP
        
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Yellow
        Write-Host "New EC2 instance created - waiting 18 seconds for WireGuard deployment..." -ForegroundColor Yellow
        Write-Host "=========================================" -ForegroundColor Yellow
        Write-Host ""
        
        Start-Sleep 18
        
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host "Setting up WireGuard connection..." -ForegroundColor Cyan
        Write-Host "=========================================" -ForegroundColor Cyan
        Write-Host ""

        Connect-WireGuard
        
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Magenta
        Write-Host "New EC2 instance created" -ForegroundColor Green
        Write-Host "WireGuard tunnel service installed" -ForegroundColor Green
        Write-Host "VPN should be operational" -ForegroundColor Green
        Write-Host "=========================================" -ForegroundColor Magenta
    }

} catch {
    Write-Host ""
    Write-Host "ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

Pause-Script