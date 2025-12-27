function New-PositionedPowerShell {
    <#
    .SYNOPSIS
        Launches a new PowerShell window positioned at a specific screen location.
    
    .DESCRIPTION
        Creates a new pwsh.exe window, optionally runs commands in it, and positions it
        in a specific docking region on a specific screen.
    
    .PARAMETER Screen
        Zero-based screen index where the window should appear.
    
    .PARAMETER Position
        Docking region name (e.g., LeftHalf, RightTopThird, Full).
    
    .PARAMETER WorkingDirectory
        Starting directory for the PowerShell session.
    
    .PARAMETER Command
        Command or array of commands to execute in the new window.
    
    .PARAMETER Title
        Window title (used for identification and user reference).
    
    .EXAMPLE
        New-PositionedPowerShell -Screen 0 -Position LeftHalf
        Opens PowerShell in left half of primary screen
    
    .EXAMPLE
        New-PositionedPowerShell -Screen 2 -Position RightTopThird -WorkingDirectory "C:\Projects" -Command "dotnet run"
        Opens PowerShell in top-right third of screen 2, navigates to directory and runs dotnet
    
    .EXAMPLE
        New-PositionedPowerShell -Screen 1 -Position Full -Command @("cd frontend", "npm run dev") -Title "Frontend Dev"
        Opens full-screen PowerShell with multiple commands and custom title
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Screen,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'LeftHalf', 'RightHalf', 'TopHalf', 'BottomHalf',
            'LeftThird', 'MiddleThird', 'RightThird',
            'TopThird', 'MiddleVerticalThird', 'BottomThird',
            'LeftTopThird', 'LeftMiddleThird', 'LeftBottomThird',
            'RightTopThird', 'RightMiddleThird', 'RightBottomThird',
            'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight',
            'Full', 'Center', 'Maximized'
        )]
        [string]$Position,
        
        [Parameter(Mandatory = $false)]
        [string]$WorkingDirectory,
        
        [Parameter(Mandatory = $false)]
        [object]$Command,
        
        [Parameter(Mandatory = $false)]
        [string]$Title = "PowerShell"
    )
    
    # Load required functions
    $scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    . "$scriptPath\Get-DockingRegion.ps1"
    . "$scriptPath\Set-WindowPosition.ps1"
    
    # Get target coordinates
    try {
        $region = Get-DockingRegion -Screen $Screen -Position $Position
    }
    catch {
        Write-Error "Failed to calculate docking region: $_"
        return $null
    }
    
    # Build command string for pwsh.exe
    $commandString = ""
    
    # Set window title first
    $commandString += "`$host.ui.RawUI.WindowTitle = '$Title'; "
    
    # Change directory if specified
    if ($WorkingDirectory) {
        $commandString += "Set-Location '$WorkingDirectory'; "
    }
    
    # Add user commands
    if ($Command) {
        if ($Command -is [array]) {
            $commandString += ($Command -join "; ")
        }
        else {
            $commandString += $Command
        }
    }
    
    # Build pwsh.exe arguments
    $pwshArgs = @(
        '-NoLogo'
        '-NoExit'
    )
    
    if ($commandString) {
        $pwshArgs += '-Command'
        $pwshArgs += $commandString
    }
    
    # Launch PowerShell
    Write-Verbose "Launching PowerShell with title '$Title'"
    Write-Verbose "Command: $commandString"
    
    try {
        $process = Start-Process -FilePath "pwsh.exe" `
            -ArgumentList $pwshArgs `
            -PassThru `
            -WindowStyle Normal
        
        if (-not $process) {
            Write-Error "Failed to start PowerShell process"
            return $null
        }
        
        Write-Verbose "Process started with PID $($process.Id)"
        
        # Initial delay to let process initialize
        Start-Sleep -Milliseconds 200
        
        # Wait for window to be created
        $maxAttempts = 30
        $attempt = 0
        $hwnd = [IntPtr]::Zero
        
        while ($attempt -lt $maxAttempts) {
            Start-Sleep -Milliseconds 100
            $process.Refresh()
            $hwnd = $process.MainWindowHandle
            
            if ($hwnd -ne [IntPtr]::Zero) {
                break
            }
            
            $attempt++
        }
        
        if ($hwnd -eq [IntPtr]::Zero) {
            # Try finding window by title as fallback
            Write-Verbose "Trying to find window by title..."
            
            # Load Win32 API if not already loaded (for FindWindow)
            if (-not ([System.Management.Automation.PSTypeName]'Win32.User32').Type) {
                $signature = @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
'@
                Add-Type -MemberDefinition $signature -Name User32 -Namespace Win32
            }
            
            $hwnd = [Win32.User32]::FindWindow($null, $Title)
            
            if ($hwnd -eq [IntPtr]::Zero) {
                Write-Warning "Could not get window handle for process $($process.Id). Window positioning skipped."
                return $process
            }
            else {
                Write-Verbose "Found window by title"
            }
        }
        
        Write-Verbose "Window handle obtained: $hwnd"
        
        # Position the window
        $positionSuccess = $false
        
        if ($Position -eq 'Maximized') {
            $positionSuccess = Set-WindowPosition -ProcessId $process.Id -Maximize
        }
        else {
            $positionSuccess = Set-WindowPosition -ProcessId $process.Id `
                -X $region.X `
                -Y $region.Y `
                -Width $region.Width `
                -Height $region.Height
        }
        
        if ($positionSuccess) {
            Write-Verbose "Window positioned successfully at $($region.Position) on screen $Screen"
        }
        else {
            Write-Warning "Failed to position window"
        }
        
        return $process
    }
    catch {
        Write-Error "Failed to create positioned PowerShell window: $_"
        return $null
    }
}

# If script is run directly, show usage example
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`nNew-PositionedPowerShell - Launch PowerShell windows in specific positions" -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Cyan
    Write-Host "`nUsage examples:" -ForegroundColor Yellow
    Write-Host "  . .\New-PositionedPowerShell.ps1" -ForegroundColor White
    Write-Host "  New-PositionedPowerShell -Screen 0 -Position LeftHalf" -ForegroundColor White
    Write-Host "  New-PositionedPowerShell -Screen 1 -Position RightTopThird -WorkingDirectory 'C:\Projects' -Command 'dotnet run'" -ForegroundColor White
    Write-Host "  New-PositionedPowerShell -Screen 2 -Position Full -Command @('cd frontend', 'npm run dev') -Title 'Frontend'" -ForegroundColor White
    Write-Host "`nRun with -? for full help" -ForegroundColor Gray
}
