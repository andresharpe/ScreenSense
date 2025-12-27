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
    
    .PARAMETER HostMode
        Window hosting mode. Options:
        - Auto: Try standard launch, fall back to ConHost if needed (default)
        - ConHost: Force classic console window via cmd.exe (most reliable)
        - Direct: Launch pwsh.exe directly without fallback
    
    .EXAMPLE
        New-PositionedPowerShell -Screen 0 -Position LeftHalf
        Opens PowerShell in left half of primary screen
    
    .EXAMPLE
        New-PositionedPowerShell -Screen 0 -Position Full -HostMode ConHost
        Forces classic console window for reliable positioning
    
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
        [string]$Title = "PowerShell",
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Auto', 'ConHost', 'Direct')]
        [string]$HostMode = 'Auto'
    )
    
    # Load required functions
    $scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    . "$scriptPath\Get-DockingRegion.ps1"
    . "$scriptPath\Set-WindowPosition.ps1"
    
    # Generate unique window title token to avoid ambiguity
    $token = (New-Guid).ToString('N').Substring(0, 8)
    $effectiveTitle = "$Title [SS-$token]"
    Write-Verbose "Unique window title: $effectiveTitle"
    
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
    
    # Escape single quotes in strings for PowerShell
    $escapedTitle = $effectiveTitle -replace "'", "''"
    $escapedWorkingDir = if ($WorkingDirectory) { $WorkingDirectory -replace "'", "''" } else { $null }
    
    # Set window title first (using unique title)
    $commandString += "`$host.ui.RawUI.WindowTitle = '$escapedTitle'; "
    
    # Change directory if specified
    if ($escapedWorkingDir) {
        $commandString += "Set-Location '$escapedWorkingDir'; "
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
    Write-Verbose "Launching PowerShell with title '$effectiveTitle', mode: $HostMode"
    Write-Verbose "Command: $commandString"
    
    try {
        # Choose launch method based on HostMode
        if ($HostMode -eq 'ConHost') {
            # Force classic console window via cmd.exe start
            # This creates a separate conhost.exe window that we can reliably position
            $cmdArgs = @("/c", "start", "`"$escapedTitle`"", "pwsh.exe") + $pwshArgs
            Write-Verbose "Using ConHost mode: cmd.exe $($cmdArgs -join ' ')"
            
            $process = Start-Process -FilePath "cmd.exe" `
                -ArgumentList $cmdArgs `
                -PassThru `
                -WindowStyle Normal
            
            # With cmd /c start, we need to wait and find the pwsh process
            Start-Sleep -Milliseconds 500
            
            # Find the pwsh process by title (most recently created)
            $pwshProcesses = Get-Process pwsh -ErrorAction SilentlyContinue | 
                Where-Object { $_.StartTime -gt (Get-Date).AddSeconds(-5) } | 
                Sort-Object StartTime -Descending
            
            if ($pwshProcesses) {
                $process = $pwshProcesses[0]
                Write-Verbose "Found pwsh process: PID $($process.Id)"
            }
            else {
                Write-Warning "Could not find launched pwsh process"
                return $null
            }
        }
        else {
            # Direct launch or Auto mode
            $process = Start-Process -FilePath "pwsh.exe" `
                -ArgumentList $pwshArgs `
                -PassThru `
                -WindowStyle Normal
        }
        
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
            Write-Verbose "MainWindowHandle is zero, attempting EnumWindows resolution..."
            
            # Ensure Set-WindowPosition is loaded (provides Get-WindowHandleByPID)
            . "$scriptPath\Set-WindowPosition.ps1"
            
            # Try EnumWindows first (most reliable for console windows)
            $handles = Get-WindowHandleByPID -ProcessId $process.Id
            
            if ($handles.Count -gt 0) {
                $hwnd = $handles[0]
                Write-Verbose "Found $($handles.Count) window(s) via EnumWindows, using first: $hwnd"
                
                # Verify which PID owns this window
                if (-not ([System.Management.Automation.PSTypeName]'ScreenSense.User32').Type) {
                    . "$scriptPath\Set-WindowPosition.ps1"
                }
                
                $ownerPid = 0
                [ScreenSense.User32]::GetWindowThreadProcessId($hwnd, [ref]$ownerPid) | Out-Null
                if ($ownerPid -ne $process.Id) {
                    Write-Warning "Window $hwnd is owned by PID $ownerPid, not $($process.Id). This may indicate process tree issues."
                }
                else {
                    Write-Verbose "Confirmed window $hwnd is owned by PID $($process.Id)"
                }
            }
            else {
                Write-Verbose "No windows found via EnumWindows, trying FindWindow by title..."
                
                # Ensure ScreenSense.User32 is loaded for FindWindow
                . "$scriptPath\Set-WindowPosition.ps1"
                
                # Give title time to be set
                Start-Sleep -Milliseconds 200
                $hwnd = [ScreenSense.User32]::FindWindow($null, $effectiveTitle)
                
                if ($hwnd -ne [IntPtr]::Zero) {
                    Write-Verbose "Found window by title: $effectiveTitle"
                }
            }
            
            # Final diagnostic if still no handle
            if ($hwnd -eq [IntPtr]::Zero) {
                $parentProc = (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)?.Parent
                Write-Warning @"
Could not get window handle for process $($process.Id).
Parent process: $(if ($parentProc) { "$($parentProc.ProcessName) (PID $($parentProc.Id))" } else { "Unknown" })
Attempted: MainWindowHandle, EnumWindows, FindWindow by title

This may indicate the process is hosted in a terminal emulator without its own window.
Consider using -HostMode ConHost parameter (when implemented) for more reliable window creation.
"@
                return $process
            }
        }
        
        Write-Verbose "Window handle obtained: $hwnd"
        
        # Position the window using the handle we found
        $positionSuccess = $false
        
        if ($Position -eq 'Maximized') {
            $positionSuccess = Set-WindowPosition -WindowHandle $hwnd -Maximize
        }
        else {
            $positionSuccess = Set-WindowPosition -WindowHandle $hwnd `
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
