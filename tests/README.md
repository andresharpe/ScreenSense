# ScreenSense Tests

## Running the Clean Window Launch Test

This test validates the complete end-to-end window launch and positioning flow.

### Prerequisites

1. **Start a brand-new PowerShell 7 console** (not Warp)
2. Ensure no ScreenSense types are already loaded in the session

### Run the Test

```powershell
cd C:\Users\andre\repos\ScreenSense
.\tests\Test-CleanWindowLaunch.ps1 -Verbose
```

### Test Options

```powershell
# Test on a specific screen and position
.\tests\Test-CleanWindowLaunch.ps1 -Screen 1 -Position LeftTopThird -Verbose

# Keep window open for manual inspection
.\tests\Test-CleanWindowLaunch.ps1 -CleanupAfter 0 -Verbose

# Test with different host mode
.\tests\Test-CleanWindowLaunch.ps1 -HostMode Direct -Verbose
```

### What the Test Validates

1. ✓ Clean session (no type conflicts)
2. ✓ Screen availability
3. ✓ Docking region calculation
4. ✓ PowerShell process launch with specified HostMode
5. ✓ Unique window title with SS-<token> suffix
6. ✓ Window handle resolution via fallback chain:
   - MainWindowHandle
   - EnumWindows by PID
   - FindWindow by title
7. ✓ HWND passed directly to Set-WindowPosition
8. ✓ Window position accuracy (within tolerance)
9. ✓ Window visibility and state
10. ✓ Focus handling (no focus stealing)

### Expected Output

The test will display color-coded output:
- **[STEP]** (Yellow) - Test phase
- **[OK]** (Green) - Validation passed
- **[FAIL]** (Red) - Validation failed
- **[INFO]** (Gray) - Diagnostic information

### Troubleshooting

**"Session has pre-existing types"**
- Start a completely new PowerShell session

**"This test must NOT be run from Warp terminal"**
- Run from native PowerShell console (`pwsh.exe`)

**"MainWindowHandle is zero"**
- Expected for ConHost mode
- Test will verify EnumWindows fallback worked correctly
