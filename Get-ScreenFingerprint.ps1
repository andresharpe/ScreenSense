function Get-ScreenFingerprint {
    <#
    .SYNOPSIS
        Generates a fingerprint based on the current screen configuration.
    
    .DESCRIPTION
        Creates a consistent hash based on connected monitors, their resolutions,
        and relative positions. The fingerprint will be the same for the same
        physical workspace setup.
    
    .EXAMPLE
        Get-ScreenFingerprint
        Returns a fingerprint like "a3f5b2c1"
    #>
    
    # Get all monitors using WMI
    $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams |
        ForEach-Object {
            $instanceName = $_.InstanceName
            # Get the display device info
            $index = [regex]::Match($instanceName, '_(\d+)$').Groups[1].Value
            @{
                Index = $index
                Width = $_.MaxHorizontalImageSize
                Height = $_.MaxVerticalImageSize
            }
        } | Sort-Object Index
    
    # Get screen resolution and position info
    Add-Type -AssemblyName System.Windows.Forms
    $screens = [System.Windows.Forms.Screen]::AllScreens | Sort-Object -Property { $_.Bounds.X }, { $_.Bounds.Y }
    
    # Build a normalized string representation
    $configString = $screens | ForEach-Object {
        $width = $_.Bounds.Width
        $height = $_.Bounds.Height
        $x = $_.Bounds.X
        $y = $_.Bounds.Y
        $primary = if ($_.Primary) { "P" } else { "S" }
        
        # Format: Primary_Width x Height @ X,Y
        "${primary}_${width}x${height}@${x},${y}"
    } | Sort-Object | Join-String -Separator "|"
    
    # Generate a hash
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($configString))
    
    # Convert to short hex string (first 8 characters)
    $fingerprint = ($hashBytes[0..3] | ForEach-Object { $_.ToString("x2") }) -join ''
    
    return [PSCustomObject]@{
        Fingerprint = $fingerprint
        ScreenCount = $screens.Count
        Configuration = $configString
        Screens = $screens | ForEach-Object {
            [PSCustomObject]@{
                Primary = $_.Primary
                Resolution = "$($_.Bounds.Width)x$($_.Bounds.Height)"
                Position = "$($_.Bounds.X),$($_.Bounds.Y)"
                DeviceName = $_.DeviceName
            }
        }
    }
}

# If script is run directly (not dot-sourced), execute the function
if ($MyInvocation.InvocationName -ne '.') {
    $result = Get-ScreenFingerprint
    
    Write-Host "`nScreen Configuration Fingerprint" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "Fingerprint: $($result.Fingerprint)" -ForegroundColor Green
    Write-Host "Screen Count: $($result.ScreenCount)" -ForegroundColor Yellow
    Write-Host "`nScreens:" -ForegroundColor Yellow
    
    foreach ($screen in $result.Screens) {
        $primaryIndicator = if ($screen.Primary) { " [PRIMARY]" } else { "" }
        Write-Host "  - $($screen.Resolution) @ $($screen.Position)$primaryIndicator" -ForegroundColor White
        Write-Host "    Device: $($screen.DeviceName)" -ForegroundColor Gray
    }
    
    Write-Host "`nConfiguration String:" -ForegroundColor Yellow
    Write-Host "  $($result.Configuration)" -ForegroundColor Gray
}
