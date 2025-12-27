function Set-WindowPosition {
    <#
    .SYNOPSIS
        Positions and resizes a window using Win32 API.
    
    .DESCRIPTION
        Takes a window handle or process and moves/resizes it to the specified coordinates.
        Can also maximize or restore windows.
    
    .PARAMETER ProcessId
        Process ID of the window to position.
    
    .PARAMETER WindowHandle
        Direct window handle (HWND) to position.
    
    .PARAMETER X
        X coordinate for window position.
    
    .PARAMETER Y
        Y coordinate for window position.
    
    .PARAMETER Width
        Window width in pixels.
    
    .PARAMETER Height
        Window height in pixels.
    
    .PARAMETER Maximize
        Switch to maximize the window instead of using coordinates.
    
    .EXAMPLE
        Set-WindowPosition -ProcessId 1234 -X 0 -Y 0 -Width 1920 -Height 1080
        Positions window to coordinates
    
    .EXAMPLE
        Set-WindowPosition -ProcessId 1234 -Maximize
        Maximizes the window
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ByProcessId')]
        [int]$ProcessId,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'ByHandle')]
        [IntPtr]$WindowHandle,
        
        [Parameter(Mandatory = $false)]
        [int]$X,
        
        [Parameter(Mandatory = $false)]
        [int]$Y,
        
        [Parameter(Mandatory = $false)]
        [int]$Width,
        
        [Parameter(Mandatory = $false)]
        [int]$Height,
        
        [Parameter(Mandatory = $false)]
        [switch]$Maximize
    )
    
    # Define Win32 API signatures
    $signature = @'
[DllImport("user32.dll")]
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

[DllImport("user32.dll")]
public static extern bool IsIconic(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern bool IsZoomed(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern IntPtr GetForegroundWindow();

[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
'@
    
    # Add type if not already loaded
    if (-not ([System.Management.Automation.PSTypeName]'Win32.User32').Type) {
        Add-Type -MemberDefinition $signature -Name User32 -Namespace Win32
    }
    
    # Get window handle
    $hwnd = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByProcessId') {
        try {
            $process = Get-Process -Id $ProcessId -ErrorAction Stop
            $hwnd = $process.MainWindowHandle
            
            if ($hwnd -eq [IntPtr]::Zero) {
                Write-Warning "Process $ProcessId does not have a main window handle"
                return $false
            }
        }
        catch {
            Write-Error "Failed to get process: $_"
            return $false
        }
    }
    else {
        $hwnd = $WindowHandle
    }
    
    # Restore window if minimized or maximized (unless we're maximizing)
    if (-not $Maximize) {
        $isMinimized = [Win32.User32]::IsIconic($hwnd)
        $isMaximized = [Win32.User32]::IsZoomed($hwnd)
        
        if ($isMinimized -or $isMaximized) {
            # SW_RESTORE = 9
            [Win32.User32]::ShowWindow($hwnd, 9) | Out-Null
            Start-Sleep -Milliseconds 50
        }
    }
    
    # Perform the window operation
    if ($Maximize) {
        # SW_MAXIMIZE = 3
        $result = [Win32.User32]::ShowWindow($hwnd, 3)
    }
    else {
        # SetWindowPos flags
        # SWP_NOZORDER = 0x0004 (don't change Z order)
        # SWP_NOACTIVATE = 0x0010 (don't activate)
        # SWP_SHOWWINDOW = 0x0040 (show window)
        $SWP_NOZORDER = 0x0004
        $SWP_SHOWWINDOW = 0x0040
        $flags = $SWP_NOZORDER -bor $SWP_SHOWWINDOW
        
        $result = [Win32.User32]::SetWindowPos(
            $hwnd,
            [IntPtr]::Zero,
            $X,
            $Y,
            $Width,
            $Height,
            $flags
        )
    }
    
    if (-not $result) {
        Write-Warning "SetWindowPos or ShowWindow failed for window handle $hwnd"
        return $false
    }
    
    return $true
}

# If script is run directly, show usage example
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`nSet-WindowPosition - Position windows using Win32 API" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "`nUsage examples:" -ForegroundColor Yellow
    Write-Host "  . .\Set-WindowPosition.ps1" -ForegroundColor White
    Write-Host "  Set-WindowPosition -ProcessId 1234 -X 0 -Y 0 -Width 1920 -Height 1080" -ForegroundColor White
    Write-Host "  Set-WindowPosition -ProcessId 1234 -Maximize" -ForegroundColor White
    Write-Host "`nRun with -? for full help" -ForegroundColor Gray
}
