# Get the directory where this script is located
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$JsonFile = Join-Path $scriptPath "packages.json"

# Check if packages.json exists
if (-not (Test-Path $JsonFile)) {
    Write-Error "packages.json not found in script directory: $scriptPath"
    exit 1
}

# Read package list
$packages = Get-Content $JsonFile | ConvertFrom-Json

# Ensure Chocolatey is installed
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey not found...."
    Write-Host "Run: Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    exit 1
} else {
    Write-Host "Chocolatey is already installed."
}

$jobs = @()

foreach ($pkg in $packages) {
    if ($pkg.winget -and $pkg.winget.Trim() -ne "") {
        Write-Host "Queuing winget installation: $($pkg.winget)"
        $job = Start-Job -ScriptBlock {
            param($packageId)
            try {
                $result = winget install --id $packageId --accept-package-agreements --accept-source-agreements
                $output = $result -join "`n"
                
                # Check for specific success/info conditions
                $isAlreadyInstalled = $output -match "No available upgrade found|No newer version was found|already installed"
                $isSuccess = ($LASTEXITCODE -eq 0) -or $isAlreadyInstalled
                
                return @{
                    Success = $isSuccess
                    PackageId = $packageId
                    Method = "winget"
                    Output = $output
                    ExitCode = $LASTEXITCODE
                    IsAlreadyInstalled = $isAlreadyInstalled
                }
            }
            catch {
                return @{
                    Success = $false
                    PackageId = $packageId
                    Method = "winget"
                    Output = $_.Exception.Message
                    ExitCode = -1
                    IsAlreadyInstalled = $false
                }
            }
        } -ArgumentList $pkg.winget
        $jobs += $job
        
    } elseif ($pkg.choco -and $pkg.choco.Trim() -ne "") {
        $job = Start-Job -ScriptBlock {
            param($packageId)
            try {
                $result = choco install $packageId -y 2>&1
                $output = $result -join "`n"
                
                # Check for specific success/info conditions
                $isAlreadyInstalled = $output -match "already installed|same version of .* is already installed"
                $isSuccess = ($LASTEXITCODE -eq 0) -or $isAlreadyInstalled
                
                return @{
                    Success = $isSuccess
                    PackageId = $packageId
                    Method = "choco"
                    Output = $output
                    ExitCode = $LASTEXITCODE
                    IsAlreadyInstalled = $isAlreadyInstalled
                }
            }
            catch {
                return @{
                    Success = $false
                    PackageId = $packageId
                    Method = "choco"
                    Output = $_.Exception.Message
                    ExitCode = -1
                    IsAlreadyInstalled = $false
                }
            }
        } -ArgumentList $pkg.choco
        $jobs += $job
        
    } else {
        Write-Warning "Skipping entry - no valid package defined: $($pkg | ConvertTo-Json -Compress)"
    }
}

# Monitor jobs in real-time and display results as they complete
if ($jobs.Count -gt 0) {
    $completedJobs = @()
    $successCount = 0
    $failureCount = 0
    $alreadyInstalledCount = 0
    
    # Poll for completed jobs
    while ($completedJobs.Count -lt $jobs.Count) {
        foreach ($job in $jobs) {
            if ($job.State -eq "Completed" -and $job -notin $completedJobs) {
                $result = Receive-Job -Job $job
                $completedJobs += $job
                
                if ($result.Success) {
                    if ($result.IsAlreadyInstalled) {
                        # Write-Host "ℹ️  ALREADY INSTALLED: $($result.Method) - $($result.PackageId)" -ForegroundColor Cyan
                        $alreadyInstalledCount++
                    } else {
                        Write-Host "✅ SUCCESS: $($result.Method) - $($result.PackageId)" -ForegroundColor Green
                        $successCount++
                    }
                } else {
                    Write-Host "❌ FAILED:  $($result.Method) - $($result.PackageId)" -ForegroundColor Red
                    # Show only the last few lines of error output to avoid spam
                    $errorLines = $result.Output -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 3
                    foreach ($line in $errorLines) {
                        Write-Host "   $line" -ForegroundColor Yellow
                    }
                    $failureCount++
                }
                
                # Clean up the completed job
                Remove-Job -Job $job
            }
        }
        
        # Small delay to avoid excessive CPU usage
        Start-Sleep -Milliseconds 500
    }
    
    Write-Host "✅ Newly Installed: $successCount" -ForegroundColor Green
    Write-Host "ℹ️ Already Installed: $alreadyInstalledCount" -ForegroundColor Cyan  
    if ($failureCount -eq 0) {
        Write-Host "✅ Failed: $failureCount" -ForegroundColor Green
    } else {
        Write-Host "❌ Failed: $failureCount" -ForegroundColor Red
    }
    Write-Host "📦 Total Processed: $($successCount + $alreadyInstalledCount + $failureCount)"
} else {
    Write-Host "No packages to install."
}
