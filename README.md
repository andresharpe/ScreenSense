# ScreenSense

Detect your physical workspace and automatically launch window layouts based on your monitor setup.

## What it does

- **Fingerprints your screen configuration** - Generates a unique ID based on connected monitors (resolution, position, count)
- **Launches positioned windows** - Opens PowerShell windows in specific screen regions with custom commands
- **Workspace automation** - Define YAML configs for different locations (home, office, etc.) that launch automatically

## Quick Start

### 1. Get your screen fingerprint
```powershell
.\Get-ScreensFingerprint.ps1
```

**Example output:**
```
Fingerprint: eff842cf
Screen Count: 3

Screens:
  - 3440x1440 @ -4190,-1465
  - 1707x1920 @ -750,-2880
  - 1536x960 @ 0,0 [PRIMARY]
```

### 2. Create a workspace config

Copy `workspace.example.yml` to `workspace.yml` and update with your fingerprint and desired window layout.

```yaml
workspaces:
  eff842cf:  # Your fingerprint
    name: "Home Office"
    windows:
      - name: "Frontend Dev"
        screen: 0
        position: LeftHalf
        workingDir: "C:\\Projects\\MyApp"
        commands:
          - "cd frontend"
          - "npm run dev"
      
      - name: "Backend API"
        screen: 0
        position: RightHalf
        workingDir: "C:\\Projects\\MyApp\\backend"
        commands:
          - "dotnet run"
```

### 3. Launch your workspace
```powershell
.\Start-ScreenSenseWorkspace.ps1
```

All windows launch automatically in their configured positions!

## Docking Regions

Instead of coordinates, use intuitive region names:

**Halves:**
- `LeftHalf`, `RightHalf`, `TopHalf`, `BottomHalf`

**Thirds (Horizontal):**
- `LeftThird`, `MiddleThird`, `RightThird`

**Thirds (Vertical):**
- `TopThird`, `MiddleVerticalThird`, `BottomThird`

**Grid 2×3 (Perfect for dev workflows):**
- `LeftTopThird`, `LeftMiddleThird`, `LeftBottomThird`
- `RightTopThird`, `RightMiddleThird`, `RightBottomThird`

**Quarters:**
- `TopLeft`, `TopRight`, `BottomLeft`, `BottomRight`

**Special:**
- `Full`, `Center`, `Maximized`

## Commands

### Get-ScreensFingerprint
Get current screen configuration and fingerprint.
```powershell
.\Get-ScreensFingerprint.ps1
```

### New-PositionedPowerShell
Launch a single PowerShell window in a specific position.
```powershell
. .\New-PositionedPowerShell.ps1
New-PositionedPowerShell -Screen 0 -Position LeftHalf -WorkingDirectory "C:\\Projects" -Command "dotnet run"
```

### Start-ScreenSenseWorkspace
Launch entire workspace from config file.
```powershell
# Launch all windows for current fingerprint
.\Start-ScreenSenseWorkspace.ps1

# Launch specific window only
.\Start-ScreenSenseWorkspace.ps1 -WindowName "Frontend Dev"

# Use different config file
.\Start-ScreenSenseWorkspace.ps1 -ConfigFile "my-workspace.yml"
```

## Requirements

- **PowerShell 7+** (pwsh.exe)
- **Windows** (uses Win32 API for window positioning)
- **powershell-yaml module** (optional, for YAML support)
  ```powershell
  Install-Module powershell-yaml
  ```
  Without this module, use JSON format instead of YAML.

## Use Cases

- **Full-stack development** - Frontend, backend, and logs in separate positioned windows
- **Multi-location work** - Different layouts for home office, work office, coffee shop
- **Grid layouts** - Browser testing in left thirds, dev servers in right thirds
- **Quick project startup** - One command to launch entire dev environment
