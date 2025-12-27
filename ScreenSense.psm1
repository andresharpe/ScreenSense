# ScreenSense PowerShell Module
# Intelligent window positioning and workspace management

$srcPath = Join-Path $PSScriptRoot "src"

# Initialize Win32 types first
. "$srcPath\Initialize-ScreenSenseTypes.ps1"

# Import all core functions
. "$srcPath\Get-DockingRegion.ps1"
. "$srcPath\Set-WindowPosition.ps1"
. "$srcPath\New-PositionedPowerShell.ps1"
. "$srcPath\Start-ScreenSenseWorkspace.ps1"
. "$srcPath\Get-ScreensFingerprint.ps1"

# Export public functions
Export-ModuleMember -Function @(
    'Get-DockingRegion',
    'Set-WindowPosition',
    'New-PositionedPowerShell',
    'Start-ScreenSenseWorkspace',
    'Get-ScreensFingerprint'
)
