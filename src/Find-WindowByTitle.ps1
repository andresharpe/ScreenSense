function Find-WindowByTitle {
    <#
    .SYNOPSIS
        Finds window handle by searching all windows for a title pattern.
    
    .PARAMETER TitlePattern
        Exact title or wildcard pattern to match (supports * and ?).
    
    .PARAMETER Exact
        If specified, requires exact title match (case-insensitive).
    
    .OUTPUTS
        IntPtr window handle, or [IntPtr]::Zero if not found.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TitlePattern,
        
        [Parameter(Mandatory = $false)]
        [switch]$Exact
    )
    
    # Ensure types are loaded
    $scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    . "$scriptPath\Initialize-ScreenSenseTypes.ps1"
    
    # Add GetWindowText if not already available
    if (-not ([System.Management.Automation.PSTypeName]'WindowTextHelper').Type) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WindowTextHelper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
'@
    }
    
    $foundHwnd = [IntPtr]::Zero
    $pattern = $TitlePattern
    
    # Create callback that searches for matching title
    $callback = {
        param($hwnd, $lParam)
        
        if ([WindowTextHelper]::IsWindowVisible($hwnd)) {
            $title = New-Object System.Text.StringBuilder 512
            $length = [WindowTextHelper]::GetWindowText($hwnd, $title, $title.Capacity)
            
            if ($length -gt 0) {
                $titleStr = $title.ToString()
                
                $isMatch = if ($Exact) {
                    $titleStr -eq $pattern
                } else {
                    $titleStr -like $pattern
                }
                
                if ($isMatch) {
                    $script:foundHwnd = $hwnd
                    Write-Verbose "Found matching window: '$titleStr' (HWND: $hwnd)"
                    return $false  # Stop enumeration
                }
            }
        }
        
        return $true  # Continue enumeration
    }
    
    # Enumerate all windows
    [ScreenSense.User32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    
    return $foundHwnd
}
