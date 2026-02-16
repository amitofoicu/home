Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# CONFIG
$Region = "ap-southeast-1"

function Stop-WireGuard {
    Write-Host "`n[1/3] Checking WireGuard..." -ForegroundColor Cyan
    
    $proc = Get-Process -Name "wireguard", "wg" -ErrorAction SilentlyContinue
    
    if ($proc) {
        Write-Host "  -> WireGuard is running. Terminating..." -ForegroundColor Yellow
        
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep -Seconds 2
        
        $proc | ForEach-Object {
            if (!$_.HasExited) {
                $_.Kill()
            }
        }
        
        Write-Host "  -> WireGuard terminated successfully" -ForegroundColor Green
    } else {
        Write-Host "  -> WireGuard is not running" -ForegroundColor Gray
    }
}

function Get-EC2Instances {
    param([string]$Region)
    
    Write-Host "`n[2/3] Fetching EC2 instances in $Region..." -ForegroundColor Cyan
    
    try {
        $InstanceIds = aws ec2 describe-instances `
            --region $Region `
            --filters "Name=instance-state-name,Values=running" `
            --query "Reservations[].Instances[].InstanceId" `
            --output text
        
        if ([string]::IsNullOrWhiteSpace($InstanceIds)) {
            Write-Host "  -> No running instances found" -ForegroundColor Gray
            return @()
        }
        
        $InstanceIdsArray = $InstanceIds -split "[\s]+" | Where-Object { $_ -ne "" }
        
        Write-Host "  Found $($InstanceIdsArray.Count) running instance(s):" -ForegroundColor White
        foreach ($id in $InstanceIdsArray) {
            $name = aws ec2 describe-tags `
                --region $Region `
                --filters "Name=resource-id,Values=$id" "Name=key,Values=Name" `
                --query "Tags[0].Value" `
                --output text
            
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = "<No Name>"
            }
            
            $instanceType = aws ec2 describe-instances `
                --region $Region `
                --instance-ids $id `
                --query "Reservations[0].Instances[0].InstanceType" `
                --output text
            
            Write-Host "    - $id | $name | running | $instanceType" -ForegroundColor DarkCyan
        }
        
        return $InstanceIdsArray
    } catch {
        Write-Host "  -> Failed to fetch instances: $_" -ForegroundColor Red
        return $null
    }
}

function Stop-EC2Instances {
    param(
        [array]$InstanceIds,
        [string]$Region
    )
    
    Write-Host "`n[3/3] Terminating EC2 instances..." -ForegroundColor Cyan
    
    if (-not $InstanceIds -or $InstanceIds.Count -eq 0) {
        Write-Host "  -> No instances to terminate" -ForegroundColor Gray
        return $true
    }
    
    try {
        $batchSize = 100
        for ($i = 0; $i -lt $InstanceIds.Count; $i += $batchSize) {
            $batch = $InstanceIds[$i..([Math]::Min($i + $batchSize - 1, $InstanceIds.Count - 1))]
            
            Write-Host "  -> Terminating batch $([Math]::Floor($i/$batchSize)+1)..." -ForegroundColor Yellow
            $result = aws ec2 terminate-instances `
                --instance-ids $batch `
                --region $Region `
                --output json | ConvertFrom-Json
            
            if ($result.TerminatingInstances) {
                Write-Host "  -> Batch terminated successfully" -ForegroundColor Green
            }
        }
        
        Write-Host "`n  -> All termination commands sent successfully" -ForegroundColor Green
        Write-Host "  -> Instances will be fully terminated in a few minutes" -ForegroundColor Gray
        
        return $true
    } catch {
        Write-Host "  -> Failed to terminate instances: $_" -ForegroundColor Red
        return $false
    }
}

# Main execution
try {
    Write-Host @"

=========================================
    AWS EC2 Instance Terminator v2.0
    Stop WireGuard first, then terminate EC2
=========================================
"@ -ForegroundColor Magenta

    Stop-WireGuard

    $instanceIds = Get-EC2Instances -Region $Region
    
    if ($instanceIds -eq $null) {
        throw "Failed to retrieve instance information"
    }

    $terminationResult = Stop-EC2Instances -InstanceIds $instanceIds -Region $Region

    Write-Host "`n=========================================" -ForegroundColor Magenta
    Write-Host "All operations completed!" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Magenta

} catch {
    Write-Host "`nError during execution:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")