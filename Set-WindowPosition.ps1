function Get-WindowHandleByPID {
    <#
    .SYNOPSIS
        Finds window handle(s) for a process ID using EnumWindows.
    
    .PARAMETER ProcessId
        Process ID to search for.
    
    .OUTPUTS
        Array of IntPtr window handles matching the PID.
    #>
    param([int]$ProcessId)
    
    # Add complete WindowEnumerator class if not already loaded
    if (-not ([System.Management.Automation.PSTypeName]'WindowEnumerator').Type) {
        $code = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WindowEnumerator {
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
        public int Area { get { return Width * Height; } }
    }
    
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    private const uint GW_OWNER = 4;
    
    public static List<IntPtr> GetWindowsForProcess(int processId) {
        List<IntPtr> windows = new List<IntPtr>();
        
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            uint pid = 0;
            GetWindowThreadProcessId(hWnd, out pid);
            
            if (pid == processId) {
                // Filter: must be visible
                if (!IsWindowVisible(hWnd)) return true;
                
                // Filter: must be top-level (no owner)
                IntPtr owner = GetWindow(hWnd, GW_OWNER);
                if (owner != IntPtr.Zero) return true;
                
                // Filter: must have reasonable size
                RECT rect;
                if (GetWindowRect(hWnd, out rect)) {
                    if (rect.Width < 50 || rect.Height < 50) return true;
                }
                
                windows.Add(hWnd);
            }
            
            return true;
        }, IntPtr.Zero);
        
        // If multiple windows found, prefer the largest
        if (windows.Count > 1) {
            windows.Sort((a, b) => {
                RECT rectA, rectB;
                GetWindowRect(a, out rectA);
                GetWindowRect(b, out rectB);
                return rectB.Area.CompareTo(rectA.Area);
            });
        }
        
        return windows;
    }
}
'@
        Add-Type -TypeDefinition $code
    }
    
    $windowList = [WindowEnumerator]::GetWindowsForProcess($ProcessId)
    return $windowList.ToArray()
}

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
    
    # Define Win32 API signatures with unique namespace to avoid conflicts
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
public static extern bool IsWindow(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern IntPtr GetForegroundWindow();

[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

[DllImport("user32.dll")]
public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

[DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

[DllImport("user32.dll")]
public static extern bool IsWindowVisible(IntPtr hWnd);

[DllImport("user32.dll")]
public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

[DllImport("user32.dll")]
public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
'@
    
    # Add type if not already loaded (use unique namespace to avoid conflicts)
    if (-not ([System.Management.Automation.PSTypeName]'ScreenSense.User32').Type) {
        Add-Type -MemberDefinition $signature -Name User32 -Namespace ScreenSense
    }
    
    # Get window handle
    $hwnd = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByProcessId') {
        try {
            $process = Get-Process -Id $ProcessId -ErrorAction Stop
            $hwnd = $process.MainWindowHandle
            
            # If MainWindowHandle is zero, use EnumWindows to find it
            if ($hwnd -eq [IntPtr]::Zero) {
                Write-Verbose "MainWindowHandle is zero for PID $ProcessId, using EnumWindows..."
                $handles = Get-WindowHandleByPID -ProcessId $ProcessId
                
                if ($handles.Count -eq 0) {
                    Write-Warning "Process $ProcessId has no visible windows"
                    return $false
                }
                
                # Use first visible window
                $hwnd = $handles[0]
                Write-Verbose "Found window handle via EnumWindows: $hwnd (total: $($handles.Count) windows)"
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
    
    # Validate HWND before attempting to position
    if (-not [ScreenSense.User32]::IsWindow($hwnd)) {
        Write-Error "Invalid window handle: $hwnd"
        return $false
    }
    
    Write-Verbose "Validated window handle: $hwnd"
    
    # Restore window if minimized or maximized (unless we're maximizing)
    if (-not $Maximize) {
        $isMinimized = [ScreenSense.User32]::IsIconic($hwnd)
        $isMaximized = [ScreenSense.User32]::IsZoomed($hwnd)
        
        if ($isMinimized -or $isMaximized) {
            # SW_RESTORE = 9
            [ScreenSense.User32]::ShowWindow($hwnd, 9) | Out-Null
            Start-Sleep -Milliseconds 50
        }
    }
    
    # Perform the window operation
    if ($Maximize) {
        # SW_MAXIMIZE = 3
        $result = [ScreenSense.User32]::ShowWindow($hwnd, 3)
    }
    else {
        # SetWindowPos flags
        # SWP_NOZORDER = 0x0004 (don't change Z order)
        # SWP_NOACTIVATE = 0x0010 (don't activate)
        # SWP_SHOWWINDOW = 0x0040 (show window)
        $SWP_NOZORDER = 0x0004
        $SWP_SHOWWINDOW = 0x0040
        $flags = $SWP_NOZORDER -bor $SWP_SHOWWINDOW
        
        $result = [ScreenSense.User32]::SetWindowPos(
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
