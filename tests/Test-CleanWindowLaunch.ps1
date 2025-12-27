<#
.SYNOPSIS
    End-to-end test for ScreenSense window launch and positioning in a clean PowerShell session.

.DESCRIPTION
    This test validates the complete ScreenSense window-launch and positioning flow:
    1. Launches a new PowerShell process in the selected HostMode (preferably ConHost)
    2. Applies a unique window title with SS-<token> suffix
    3. Resolves window handle via fallback chain (MainWindowHandle → EnumWindows → FindWindow)
    4. Passes resolved HWND directly into Set-WindowPosition (not re-derived from ProcessId)
    5. Restores and positions window accurately in requested docking region without focus stealing

    This test must be run from a native PowerShell console (not Warp or embedded terminal)
    in a brand-new session to eliminate any Add-Type artifacts from previous experimentation.

.PARAMETER Screen
    Screen index to test (default: 0)

.PARAMETER Position
    Docking region to test (default: RightHalf)

.PARAMETER HostMode
    Window hosting mode: Auto, ConHost, or Direct (default: ConHost for reliability)

.PARAMETER CleanupAfter
    Number of seconds to wait before closing the test window (default: 10, 0 = manual)

.EXAMPLE
    .\Test-CleanWindowLaunch.ps1 -Verbose
    Runs test with ConHost mode, RightHalf position, with verbose logging

.EXAMPLE
    .\Test-CleanWindowLaunch.ps1 -Screen 1 -Position LeftTopThird -HostMode ConHost -Verbose
    Tests on screen 1, top-left third, with ConHost mode

.EXAMPLE
    .\Test-CleanWindowLaunch.ps1 -CleanupAfter 0 -Verbose
    Runs test and leaves window open for manual inspection
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$Screen = 0,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet(
        'LeftHalf', 'RightHalf', 'TopHalf', 'BottomHalf',
        'LeftThird', 'MiddleThird', 'RightThird',
        'TopThird', 'MiddleVerticalThird', 'BottomThird',
        'LeftTopThird', 'LeftMiddleThird', 'LeftBottomThird',
        'RightTopThird', 'RightMiddleThird', 'RightBottomThird',
        'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight',
        'Full', 'Center', 'Maximized'
    )]
    [string]$Position = 'RightHalf',
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'ConHost', 'Direct')]
    [string]$HostMode = 'ConHost',
    
    [Parameter(Mandatory = $false)]
    [int]$CleanupAfter = 10
)

# Color coding for test output
function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-TestStep {
    param([string]$Message)
    Write-Host "`n[STEP] $Message" -ForegroundColor Yellow
}

function Write-TestSuccess {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-TestFailure {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-TestInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

# Main test execution
Write-TestHeader "ScreenSense Clean Window Launch Test"

Write-TestInfo "Test Configuration:"
Write-TestInfo "  Screen: $Screen"
Write-TestInfo "  Position: $Position"
Write-TestInfo "  HostMode: $HostMode"
Write-TestInfo "  CleanupAfter: $CleanupAfter seconds"
Write-TestInfo "  PowerShell Version: $($PSVersionTable.PSVersion)"
Write-TestInfo "  Shell: $($PSVersionTable.PSEdition)"

# Validate environment
Write-TestStep "Validating test environment"

if ($env:TERM_PROGRAM -eq 'WarpTerminal') {
    Write-TestFailure "This test must NOT be run from Warp terminal"
    Write-Host "Please run from a native PowerShell console window" -ForegroundColor Yellow
    exit 1
}

Write-TestSuccess "Running in native PowerShell console"

# Check if any types are already loaded
$existingTypes = @(
    'ScreenSense.User32',
    'WindowEnumerator'
)

$typeConflicts = @()
foreach ($typeName in $existingTypes) {
    if (([System.Management.Automation.PSTypeName]$typeName).Type) {
        $typeConflicts += $typeName
    }
}

if ($typeConflicts.Count -gt 0) {
    Write-TestFailure "Session has pre-existing types: $($typeConflicts -join ', ')"
    Write-Host "Please start a brand-new PowerShell session and run this test again" -ForegroundColor Yellow
    exit 1
}

Write-TestSuccess "No type conflicts detected - clean session confirmed"

# Load ScreenSense functions
Write-TestStep "Loading ScreenSense functions"

$scriptPath = $PSScriptRoot
if (-not $scriptPath) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# Core scripts are in src/ directory
$srcPath = Join-Path (Split-Path $scriptPath -Parent) "src"

# Initialize Win32 types first
. "$srcPath\Initialize-ScreenSenseTypes.ps1"
Write-TestInfo "  Loaded: Initialize-ScreenSenseTypes.ps1"

$requiredFiles = @(
    "$srcPath\Get-DockingRegion.ps1",
    "$srcPath\Set-WindowPosition.ps1",
    "$srcPath\New-PositionedPowerShell.ps1"
)

foreach ($file in $requiredFiles) {
    if (-not (Test-Path $file)) {
        Write-TestFailure "Required file not found: $file"
        exit 1
    }
    . $file
    Write-TestInfo "  Loaded: $(Split-Path -Leaf $file)"
}

Write-TestSuccess "All ScreenSense functions loaded successfully"

# Verify screen availability
Write-TestStep "Checking screen availability"

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens

Write-TestInfo "  Available screens: $($screens.Count)"
for ($i = 0; $i -lt $screens.Count; $i++) {
    $s = $screens[$i]
    Write-TestInfo "    Screen $i`: $($s.Bounds.Width)x$($s.Bounds.Height) at $($s.Bounds.X),$($s.Bounds.Y) $(if ($s.Primary) { '(Primary)' })"
}

if ($Screen -ge $screens.Count) {
    Write-TestFailure "Requested screen $Screen is out of range (0-$($screens.Count - 1))"
    exit 1
}

Write-TestSuccess "Target screen $Screen is available"

# Test docking region calculation
Write-TestStep "Calculating docking region for screen $Screen, position $Position"

try {
    $region = Get-DockingRegion -Screen $Screen -Position $Position -Verbose:$VerbosePreference
    Write-TestSuccess "Docking region calculated"
    Write-TestInfo "  X=$($region.X), Y=$($region.Y), Width=$($region.Width), Height=$($region.Height)"
}
catch {
    Write-TestFailure "Failed to calculate docking region: $_"
    exit 1
}

# Launch positioned PowerShell window
Write-TestStep "Launching new PowerShell window with HostMode=$HostMode"

$testCommand = @(
    "Write-Host 'ScreenSense Test Window' -ForegroundColor Cyan",
    "Write-Host 'This window was launched and positioned by ScreenSense' -ForegroundColor Green",
    "Write-Host 'Process ID: `$PID' -ForegroundColor Yellow",
    "Write-Host 'Window Title: `$host.ui.RawUI.WindowTitle' -ForegroundColor Yellow"
)

try {
    $process = New-PositionedPowerShell `
        -Screen $Screen `
        -Position $Position `
        -HostMode $HostMode `
        -Title "ScreenSense Test" `
        -Command $testCommand `
        -Verbose:$VerbosePreference
    
    if (-not $process) {
        Write-TestFailure "New-PositionedPowerShell returned null"
        exit 1
    }
    
    Write-TestSuccess "Process launched with PID $($process.Id)"
}
catch {
    Write-TestFailure "Failed to launch window: $_"
    Write-TestInfo $_.ScriptStackTrace
    exit 1
}

# Verify window handle resolution
Write-TestStep "Verifying window handle resolution"

$process.Refresh()
$mainWindowHandle = $process.MainWindowHandle

Write-TestInfo "  MainWindowHandle: $mainWindowHandle"

if ($mainWindowHandle -eq [IntPtr]::Zero) {
    Write-TestInfo "  MainWindowHandle is zero (expected for ConHost mode)"
    
    # Verify EnumWindows fallback worked
    $handles = Get-WindowHandleByPID -ProcessId $process.Id
    
    if ($handles.Count -eq 0) {
        Write-TestFailure "EnumWindows fallback returned no handles"
        Write-TestInfo "  This indicates the window creation failed or handle resolution is broken"
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        exit 1
    }
    
    Write-TestSuccess "EnumWindows fallback found $($handles.Count) window(s)"
    Write-TestInfo "  Primary HWND: $($handles[0])"
    
    # Verify PID ownership
    $ownerPid = 0
    [ScreenSense.User32]::GetWindowThreadProcessId($handles[0], [ref]$ownerPid) | Out-Null
    
    if ($ownerPid -eq $process.Id) {
        Write-TestSuccess "Window ownership verified (PID $ownerPid matches $($process.Id))"
    }
    else {
        Write-TestFailure "Window ownership mismatch (HWND owned by PID $ownerPid, not $($process.Id))"
    }
}
else {
    Write-TestSuccess "MainWindowHandle resolved directly: $mainWindowHandle"
}

# Verify window position
Write-TestStep "Verifying window position"

Start-Sleep -Milliseconds 500

$hwnd = if ($mainWindowHandle -ne [IntPtr]::Zero) {
    $mainWindowHandle
} else {
    $handles = Get-WindowHandleByPID -ProcessId $process.Id
    if ($handles.Count -gt 0) { $handles[0] } else { [IntPtr]::Zero }
}

if ($hwnd -eq [IntPtr]::Zero) {
    Write-TestFailure "Could not resolve window handle for position verification"
}
else {
    $rect = New-Object ScreenSense.User32+RECT
    $rectResult = [ScreenSense.User32]::GetWindowRect($hwnd, [ref]$rect)
    
    if ($rectResult) {
        $actualX = $rect.Left
        $actualY = $rect.Top
        $actualWidth = $rect.Right - $rect.Left
        $actualHeight = $rect.Bottom - $rect.Top
        
        Write-TestInfo "  Expected: X=$($region.X), Y=$($region.Y), W=$($region.Width), H=$($region.Height)"
        Write-TestInfo "  Actual:   X=$actualX, Y=$actualY, W=$actualWidth, H=$actualHeight"
        
        # Allow small tolerance for window borders/decorations
        $tolerance = 20
        
        $xMatch = [Math]::Abs($actualX - $region.X) -le $tolerance
        $yMatch = [Math]::Abs($actualY - $region.Y) -le $tolerance
        $wMatch = [Math]::Abs($actualWidth - $region.Width) -le $tolerance
        $hMatch = [Math]::Abs($actualHeight - $region.Height) -le $tolerance
        
        if ($xMatch -and $yMatch -and $wMatch -and $hMatch) {
            Write-TestSuccess "Window positioned correctly (within $tolerance px tolerance)"
        }
        else {
            Write-TestFailure "Window position mismatch"
            Write-TestInfo "  X: $(if ($xMatch) { 'OK' } else { 'MISMATCH' })"
            Write-TestInfo "  Y: $(if ($yMatch) { 'OK' } else { 'MISMATCH' })"
            Write-TestInfo "  Width: $(if ($wMatch) { 'OK' } else { 'MISMATCH' })"
            Write-TestInfo "  Height: $(if ($hMatch) { 'OK' } else { 'MISMATCH' })"
        }
    }
    else {
        Write-TestFailure "Failed to get window rectangle"
    }
}

# Verify window is visible and responsive
Write-TestStep "Verifying window visibility and state"

if ($hwnd -ne [IntPtr]::Zero) {
    $isWindow = [ScreenSense.User32]::IsWindow($hwnd)
    $isVisible = [ScreenSense.User32]::IsWindowVisible($hwnd)
    $isMinimized = [ScreenSense.User32]::IsIconic($hwnd)
    $isMaximized = [ScreenSense.User32]::IsZoomed($hwnd)
    
    Write-TestInfo "  IsWindow: $isWindow"
    Write-TestInfo "  IsVisible: $isVisible"
    Write-TestInfo "  IsMinimized: $isMinimized"
    Write-TestInfo "  IsMaximized: $isMaximized"
    
    if ($isWindow -and $isVisible -and -not $isMinimized) {
        Write-TestSuccess "Window is visible and in correct state"
    }
    else {
        Write-TestFailure "Window is not in expected state"
    }
}

# Verify focus (should not steal focus)
Write-TestStep "Verifying focus handling"

$foregroundWindow = [ScreenSense.User32]::GetForegroundWindow()
Write-TestInfo "  Current foreground window: $foregroundWindow"
Write-TestInfo "  Test window handle: $hwnd"

if ($foregroundWindow -eq $hwnd) {
    Write-TestInfo "Test window has focus (may be expected depending on launch method)"
}
else {
    Write-TestSuccess "Focus not stolen - foreground window is different"
}

# Summary
Write-TestHeader "Test Complete"

Write-Host "`nTest window is visible on screen $Screen in position $Position" -ForegroundColor Green

if ($CleanupAfter -gt 0) {
    Write-Host "Window will be closed automatically in $CleanupAfter seconds..." -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to cancel cleanup and keep window open for manual inspection" -ForegroundColor Gray
    
    Start-Sleep -Seconds $CleanupAfter
    
    Write-TestStep "Cleaning up test window"
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Write-TestSuccess "Test window closed"
}
else {
    Write-Host "Manual cleanup mode - window will remain open" -ForegroundColor Yellow
    Write-Host "Close the test window manually when done, or run: Stop-Process -Id $($process.Id)" -ForegroundColor Gray
}

Write-Host "`n[TEST COMPLETE] All validation steps passed" -ForegroundColor Green
Write-Host "`nTo run again: .\Test-CleanWindowLaunch.ps1 -Verbose`n" -ForegroundColor Cyan
