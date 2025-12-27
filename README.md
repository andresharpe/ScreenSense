# ScreenSense

Detect your physical workspace by fingerprinting your monitor setup.

## What it does

Generates a unique fingerprint based on your connected monitors (resolution, position, count). Use it to automatically detect whether you're at home, work, or anywhere else—perfect for applying location-specific configs.

## Usage

```powershell
.\Get-ScreenFingerprint.ps1
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

Same monitor setup = same fingerprint. Different location = different fingerprint.
