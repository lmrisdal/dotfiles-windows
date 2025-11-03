# Chris Titus Tech WinUtil with configuration
Write-Host "Running Chris Titus Tech WinUtil with configuration..." -ForegroundColor Cyan

try {
    # Get the directory where this script is located
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $configPath = Join-Path $scriptPath "winutil.json"
    
    # Check if config file exists
    if (-not (Test-Path $configPath)) {
        Write-Warning "winutil.json not found in script directory: $scriptPath"
        Write-Host "Running WinUtil without configuration file..."
        iex "& { $(irm https://christitus.com/win) }"
    } else {
        Write-Host "Using configuration file: $configPath"
        iex "& { $(irm https://christitus.com/win) } -Config `"$configPath`" -Run"
    }
    
    Write-Host "WinUtil execution completed." -ForegroundColor Green
}
catch {
    Write-Error "Failed to run WinUtil: $($_.Exception.Message)"
    Write-Host "You can try running it manually with:"
    Write-Host "iex `"& { `$(irm https://christitus.com/win) }`""
    exit 1
}