function Start-ScreenSenseWorkspace {
    <#
    .SYNOPSIS
        Launches a workspace configuration based on the current screen fingerprint.
    
    .DESCRIPTION
        Reads a YAML configuration file containing workspace definitions for different
        screen fingerprints. Automatically detects the current screen configuration and
        launches the corresponding windows.
    
    .PARAMETER ConfigFile
        Path to the YAML configuration file. Defaults to workspace.yml in current directory.
    
    .PARAMETER WindowName
        Optional. Launch only a specific window by name instead of all windows.
    
    .PARAMETER Fingerprint
        Optional. Override fingerprint detection and use a specific fingerprint.
    
    .EXAMPLE
        Start-ScreenSenseWorkspace
        Launches all windows for the current screen configuration
    
    .EXAMPLE
        Start-ScreenSenseWorkspace -ConfigFile "C:\Config\dev-workspace.yml"
        Uses a specific config file
    
    .EXAMPLE
        Start-ScreenSenseWorkspace -WindowName "Backend API"
        Launches only the "Backend API" window
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigFile = "workspace.yml",
        
        [Parameter(Mandatory = $false)]
        [string]$WindowName,
        
        [Parameter(Mandatory = $false)]
        [string]$Fingerprint
    )
    
    # Load required functions
    $scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    . "$scriptPath\Get-ScreensFingerprint.ps1"
    . "$scriptPath\New-PositionedPowerShell.ps1"
    
    # Check if config file exists
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Configuration file not found: $ConfigFile"
        return
    }
    
    # Get current fingerprint if not provided
    if (-not $Fingerprint) {
        Write-Host "Detecting screen configuration..." -ForegroundColor Cyan
        $screenInfo = Get-ScreensFingerprint
        $Fingerprint = $screenInfo.Fingerprint
        Write-Host "Fingerprint: $Fingerprint" -ForegroundColor Green
    }
    
    # Parse YAML config
    Write-Host "Loading configuration from $ConfigFile..." -ForegroundColor Cyan
    
    try {
        # Try using powershell-yaml module if available
        if (Get-Module -ListAvailable -Name powershell-yaml) {
            Import-Module powershell-yaml -ErrorAction Stop
            $config = Get-Content $ConfigFile -Raw | ConvertFrom-Yaml
        }
        else {
            # Fallback to JSON (user can convert YAML to JSON or use JSON directly)
            Write-Warning "powershell-yaml module not found. Attempting to parse as JSON..."
            $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json -AsHashtable
        }
    }
    catch {
        Write-Error "Failed to parse configuration file: $_"
        Write-Host "`nTip: Install powershell-yaml module: Install-Module powershell-yaml" -ForegroundColor Yellow
        return
    }
    
    # Find workspace for current fingerprint
    if (-not $config.workspaces) {
        Write-Error "Invalid configuration: 'workspaces' key not found"
        return
    }
    
    $workspace = $config.workspaces[$Fingerprint]
    
    if (-not $workspace) {
        Write-Error "No workspace configuration found for fingerprint: $Fingerprint"
        Write-Host "`nAvailable fingerprints in config:" -ForegroundColor Yellow
        $config.workspaces.Keys | ForEach-Object {
            $name = $config.workspaces[$_].name
            Write-Host "  - $_ $(if ($name) { "($name)" })" -ForegroundColor Gray
        }
        return
    }
    
    $workspaceName = $workspace.name
    Write-Host "Loading workspace: $workspaceName" -ForegroundColor Green
    
    # Get windows to launch
    $windowsToLaunch = @()
    
    if ($WindowName) {
        # Launch specific window
        $window = $workspace.windows | Where-Object { $_.name -eq $WindowName }
        if (-not $window) {
            Write-Error "Window '$WindowName' not found in workspace"
            Write-Host "`nAvailable windows:" -ForegroundColor Yellow
            $workspace.windows | ForEach-Object {
                Write-Host "  - $($_.name)" -ForegroundColor Gray
            }
            return
        }
        $windowsToLaunch = @($window)
    }
    else {
        # Launch all windows
        $windowsToLaunch = $workspace.windows
    }
    
    if ($windowsToLaunch.Count -eq 0) {
        Write-Warning "No windows defined in workspace"
        return
    }
    
    # Launch windows
    Write-Host "`nLaunching $($windowsToLaunch.Count) window(s)..." -ForegroundColor Cyan
    
    $launched = 0
    foreach ($window in $windowsToLaunch) {
        $windowTitle = $window.name
        $screen = $window.screen
        $position = $window.position
        $workingDir = $window.workingDir
        $commands = $window.commands
        
        Write-Host "`n[$($launched + 1)/$($windowsToLaunch.Count)] Launching: $windowTitle" -ForegroundColor Yellow
        Write-Host "  Screen: $screen, Position: $position" -ForegroundColor Gray
        
        $params = @{
            Screen = $screen
            Position = $position
            Title = $windowTitle
        }
        
        if ($workingDir) {
            $params.WorkingDirectory = $workingDir
            Write-Host "  Working Directory: $workingDir" -ForegroundColor Gray
        }
        
        if ($commands) {
            $params.Command = $commands
            Write-Host "  Commands: $($commands.Count) command(s)" -ForegroundColor Gray
        }
        
        try {
            $process = New-PositionedPowerShell @params
            
            if ($process) {
                Write-Host "  ✓ Launched (PID: $($process.Id))" -ForegroundColor Green
                $launched++
            }
            else {
                Write-Warning "  ✗ Failed to launch window"
            }
        }
        catch {
            Write-Error "  ✗ Error launching window: $_"
        }
        
        # Brief delay between launches
        if ($launched -lt $windowsToLaunch.Count) {
            Start-Sleep -Milliseconds 300
        }
    }
    
    Write-Host "`n✓ Workspace launched successfully: $launched/$($windowsToLaunch.Count) windows" -ForegroundColor Green
}

# If script is run directly, show usage example
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`nStart-ScreenSenseWorkspace - Launch workspace configurations" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "`nUsage examples:" -ForegroundColor Yellow
    Write-Host "  . .\Start-ScreenSenseWorkspace.ps1" -ForegroundColor White
    Write-Host "  Start-ScreenSenseWorkspace" -ForegroundColor White
    Write-Host "  Start-ScreenSenseWorkspace -ConfigFile 'dev-workspace.yml'" -ForegroundColor White
    Write-Host "  Start-ScreenSenseWorkspace -WindowName 'Backend API'" -ForegroundColor White
    Write-Host "`nRun with -? for full help" -ForegroundColor Gray
}
