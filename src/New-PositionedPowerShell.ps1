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
    
    # Load required functions (all in same src directory)
    $scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    
    # Initialize Win32 types first (needed for FindWindow, GetWindowThreadProcessId, etc.)
    . "$scriptPath\Initialize-ScreenSenseTypes.ps1"
    
    . "$scriptPath\Get-DockingRegion.ps1"
    . "$scriptPath\Set-WindowPosition.ps1"
    . "$scriptPath\Find-WindowByTitle.ps1"
    
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
    
    # Launch PowerShell
    Write-Verbose "Launching PowerShell with title '$effectiveTitle', mode: $HostMode"
    Write-Verbose "Command: $commandString"
    
    try {
        # Choose launch method based on HostMode
        if ($HostMode -eq 'ConHost') {
            # Force classic console window via cmd.exe start
            # Use -EncodedCommand to avoid escaping issues with cmd.exe
            $commandBytes = [System.Text.Encoding]::Unicode.GetBytes($commandString)
            $encodedCommand = [Convert]::ToBase64String($commandBytes)
            
            $pwshArgs = @(
                '-NoLogo'
                '-NoExit'
                '-EncodedCommand'
                $encodedCommand
            )
            
            $cmdArgs = @("/c", "start", "`"$escapedTitle`"", "pwsh.exe") + $pwshArgs
            Write-Verbose "Using ConHost mode with EncodedCommand"
            
            $process = Start-Process -FilePath "cmd.exe" `
                -ArgumentList $cmdArgs `
                -PassThru `
                -WindowStyle Normal
            
            # With cmd /c start, we need to wait and find the pwsh process
            Start-Sleep -Milliseconds 800
            
            # Find the pwsh process by title (most recently created)
            $pwshProcesses = Get-Process pwsh -ErrorAction SilentlyContinue | 
                Where-Object { $_.StartTime -gt (Get-Date).AddSeconds(-10) } | 
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
            # Direct launch or Auto mode - use -Command instead
            $pwshArgs = @(
                '-NoLogo'
                '-NoExit'
            )
            
            if ($commandString) {
                $pwshArgs += '-Command'
                $pwshArgs += $commandString
            }
            
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
        
        # Initial delay to let process and window initialize
        # ConHost mode needs more time as cmd.exe spawns pwsh.exe which then creates console
        Start-Sleep -Milliseconds 500
        
        # Wait for window to be created - try MainWindowHandle first
        $maxAttempts = 50
        $attempt = 0
        $hwnd = [IntPtr]::Zero
        
        while ($attempt -lt $maxAttempts) {
            Start-Sleep -Milliseconds 100
            $process.Refresh()
            $hwnd = $process.MainWindowHandle
            
            if ($hwnd -ne [IntPtr]::Zero) {
                Write-Verbose "MainWindowHandle resolved after $($attempt * 100)ms"
                break
            }
            
            # After 1 second, also try EnumWindows in parallel
            if ($attempt -gt 10) {
                $handles = Get-WindowHandleByPID -ProcessId $process.Id
                if ($handles.Count -gt 0) {
                    $hwnd = $handles[0]
                    Write-Verbose "EnumWindows found handle after $($attempt * 100)ms"
                    break
                }
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
                
                # Verify which PID owns this window (type should be loaded at this point)
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
                Write-Verbose "No windows found via EnumWindows for pwsh PID"
                
                # In ConHost mode, the window might be owned by conhost.exe, not pwsh.exe
                # Try to find conhost processes that started around the same time
                if ($HostMode -eq 'ConHost') {
                    Write-Verbose "Searching for conhost.exe windows (ConHost mode)..."
                    $conhostProcesses = Get-Process conhost -ErrorAction SilentlyContinue | 
                        Where-Object { $_.StartTime -gt (Get-Date).AddSeconds(-10) } | 
                        Sort-Object StartTime -Descending
                    
                    foreach ($conhost in $conhostProcesses) {
                        $conhostHandles = Get-WindowHandleByPID -ProcessId $conhost.Id
                        if ($conhostHandles.Count -gt 0) {
                            $hwnd = $conhostHandles[0]
                            Write-Verbose "Found conhost window: PID $($conhost.Id), HWND $hwnd"
                            break
                        }
                    }
                }
                
                # Final attempt: enumerate all windows and search by title pattern
                if ($hwnd -eq [IntPtr]::Zero) {
                    Write-Verbose "Final attempt: searching all windows by title pattern..."
                    
                    for ($titleAttempt = 0; $titleAttempt -lt 20; $titleAttempt++) {
                        Start-Sleep -Milliseconds 250
                        $hwnd = Find-WindowByTitle -TitlePattern $effectiveTitle -Exact -Verbose:$VerbosePreference
                        
                        if ($hwnd -ne [IntPtr]::Zero) {
                            Write-Verbose "Found window by enumerating all windows after $($titleAttempt * 250)ms"
                            break
                        }
                    }
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
