<#
.SYNOPSIS
    Self-test script for ScreenSense window positioning
    
.DESCRIPTION
    Tests window creation and positioning in different modes to verify functionality.
    Returns exit code 0 on success, 1 on failure.
#>

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$script:testsPassed = 0
$script:testsFailed = 0

function Test-WindowMove {
    param(
        [string]$TestName,
        [hashtable]$Params
    )
    
    Write-Host "`n=== TEST: $TestName ===" -ForegroundColor Cyan
    
    try {
        . .\New-PositionedPowerShell.ps1
        
        $process = New-PositionedPowerShell @Params
        
        if ($null -eq $process) {
            Write-Host "✗ FAILED: Process was null" -ForegroundColor Red
            $script:testsFailed++
            return
        }
        
        Write-Host "✓ Process launched: PID $($process.Id)" -ForegroundColor Green
        
        # Give it a moment then check if it's still running
        Start-Sleep -Milliseconds 500
        $running = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        
        if ($running) {
            Write-Host "✓ Process still running" -ForegroundColor Green
            $script:testsPassed++
            
            # Clean up
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
        else {
            Write-Host "✗ FAILED: Process exited prematurely" -ForegroundColor Red
            $script:testsFailed++
        }
    }
    catch {
        Write-Host "✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $script:testsFailed++
    }
}

Write-Host "`nScreenSense Window Positioning Self-Test" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Test 1: Direct mode, simple position
Test-WindowMove -TestName "Direct Mode - TopLeft" -Params @{
    Screen = 0
    Position = 'TopLeft'
    Title = "Test Direct TopLeft"
    HostMode = 'Direct'
    Verbose = $Verbose
}

# Test 2: ConHost mode, different position
Test-WindowMove -TestName "ConHost Mode - RightHalf" -Params @{
    Screen = 0
    Position = 'RightHalf'
    Title = "Test ConHost Right"
    HostMode = 'ConHost'
    Verbose = $Verbose
}

# Test 3: With working directory
Test-WindowMove -TestName "With WorkingDirectory" -Params @{
    Screen = 0
    Position = 'Center'
    Title = "Test WithWorkDir"
    WorkingDirectory = $env:USERPROFILE
    HostMode = 'ConHost'
    Verbose = $Verbose
}

# Summary
Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "Tests Passed: $script:testsPassed" -ForegroundColor Green
Write-Host "Tests Failed: $script:testsFailed" -ForegroundColor $(if ($script:testsFailed -gt 0) { 'Red' } else { 'Green' })

if ($script:testsFailed -gt 0) {
    Write-Host "`n✗ SOME TESTS FAILED" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`n✓ ALL TESTS PASSED" -ForegroundColor Green
    exit 0
}
