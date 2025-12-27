# Workspaces

PowerShell scripts for managing workspace configurations based on screen fingerprints.

## Overview

This project helps you automatically detect and configure your workspace based on the physical monitor setup. Each unique monitor configuration gets a fingerprint that you can use to apply specific settings for different locations (home, office, holiday home, etc.).

## Scripts

### Get-ScreenFingerprint.ps1

Generates a consistent fingerprint based on your current screen configuration.

**Usage:**
```powershell
.\Get-ScreenFingerprint.ps1
```

**Output:**
- Fingerprint: A short hex string (e.g., `a3f5b2c1`) that uniquely identifies your monitor setup
- Screen count and details
- Configuration string showing all screens with their resolutions and positions

**Example:**
```powershell
PS> .\Get-ScreenFingerprint.ps1

Screen Configuration Fingerprint
=================================
Fingerprint: a3f5b2c1
Screen Count: 2

Screens:
  - 2560x1440 @ 0,0 [PRIMARY]
    Device: \\.\DISPLAY1
  - 1920x1080 @ 2560,0
    Device: \\.\DISPLAY2

Configuration String:
  P_2560x1440@0,0|S_1920x1080@2560,0
```

## Use Cases

1. **Workspace Detection**: Automatically detect which physical location you're working from
2. **Configuration Management**: Apply location-specific settings (wallpapers, window layouts, etc.)
3. **Documentation**: Keep track of different workspace setups

## Future Enhancements

- Save known workspace configurations with names
- Auto-apply workspace-specific settings
- Integration with window management tools
