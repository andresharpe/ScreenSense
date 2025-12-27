function Get-DockingRegion {
    <#
    .SYNOPSIS
        Calculates window coordinates for a docking region on a specific screen.
    
    .DESCRIPTION
        Given a screen index and position name, returns the X, Y, Width, and Height
        coordinates for positioning a window in that docking region.
    
    .PARAMETER Screen
        Zero-based screen index. Use 0 for primary screen.
    
    .PARAMETER Position
        Docking region name. Supported values:
        - Halves: LeftHalf, RightHalf, TopHalf, BottomHalf
        - Thirds (horizontal): LeftThird, MiddleThird, RightThird
        - Thirds (vertical): TopThird, MiddleVerticalThird, BottomThird
        - Grid 2x3: LeftTopThird, LeftMiddleThird, LeftBottomThird, RightTopThird, RightMiddleThird, RightBottomThird
        - Quarters: TopLeft, TopRight, BottomLeft, BottomRight
        - Special: Full, Center, Maximized
    
    .EXAMPLE
        Get-DockingRegion -Screen 0 -Position LeftHalf
        Returns coordinates for left half of primary screen
    
    .EXAMPLE
        Get-DockingRegion -Screen 2 -Position RightTopThird
        Returns coordinates for top-right third of screen 2
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Screen,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'LeftHalf', 'RightHalf', 'TopHalf', 'BottomHalf',
            'LeftThird', 'MiddleThird', 'RightThird',
            'TopThird', 'MiddleVerticalThird', 'BottomThird',
            'LeftTopThird', 'LeftMiddleThird', 'LeftBottomThird',
            'RightTopThird', 'RightMiddleThird', 'RightBottomThird',
            'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight',
            'Full', 'Center', 'Maximized'
        )]
        [string]$Position
    )
    
    # Load System.Windows.Forms to get screen information
    Add-Type -AssemblyName System.Windows.Forms
    
    $screens = [System.Windows.Forms.Screen]::AllScreens
    
    if ($Screen -ge $screens.Count) {
        throw "Screen index $Screen is out of range. Available screens: 0-$($screens.Count - 1)"
    }
    
    $targetScreen = $screens[$Screen]
    $bounds = $targetScreen.Bounds
    
    $x = $bounds.X
    $y = $bounds.Y
    $width = $bounds.Width
    $height = $bounds.Height
    
    # Calculate position based on docking region
    switch ($Position) {
        # Halves
        'LeftHalf' {
            $width = [math]::Floor($width / 2)
        }
        'RightHalf' {
            $x += [math]::Floor($width / 2)
            $width = [math]::Ceiling($width / 2)
        }
        'TopHalf' {
            $height = [math]::Floor($height / 2)
        }
        'BottomHalf' {
            $y += [math]::Floor($height / 2)
            $height = [math]::Ceiling($height / 2)
        }
        
        # Thirds (horizontal)
        'LeftThird' {
            $width = [math]::Floor($width / 3)
        }
        'MiddleThird' {
            $x += [math]::Floor($width / 3)
            $width = [math]::Floor($width / 3)
        }
        'RightThird' {
            $x += [math]::Floor($width / 3) * 2
            $width = [math]::Ceiling($width / 3)
        }
        
        # Thirds (vertical)
        'TopThird' {
            $height = [math]::Floor($height / 3)
        }
        'MiddleVerticalThird' {
            $y += [math]::Floor($height / 3)
            $height = [math]::Floor($height / 3)
        }
        'BottomThird' {
            $y += [math]::Floor($height / 3) * 2
            $height = [math]::Ceiling($height / 3)
        }
        
        # Grid 2x3 (left column)
        'LeftTopThird' {
            $width = [math]::Floor($width / 2)
            $height = [math]::Floor($height / 3)
        }
        'LeftMiddleThird' {
            $width = [math]::Floor($width / 2)
            $y += [math]::Floor($height / 3)
            $height = [math]::Floor($height / 3)
        }
        'LeftBottomThird' {
            $width = [math]::Floor($width / 2)
            $y += [math]::Floor($height / 3) * 2
            $height = [math]::Ceiling($height / 3)
        }
        
        # Grid 2x3 (right column)
        'RightTopThird' {
            $x += [math]::Floor($width / 2)
            $width = [math]::Ceiling($width / 2)
            $height = [math]::Floor($height / 3)
        }
        'RightMiddleThird' {
            $x += [math]::Floor($width / 2)
            $width = [math]::Ceiling($width / 2)
            $y += [math]::Floor($height / 3)
            $height = [math]::Floor($height / 3)
        }
        'RightBottomThird' {
            $x += [math]::Floor($width / 2)
            $width = [math]::Ceiling($width / 2)
            $y += [math]::Floor($height / 3) * 2
            $height = [math]::Ceiling($height / 3)
        }
        
        # Quarters
        'TopLeft' {
            $width = [math]::Floor($width / 2)
            $height = [math]::Floor($height / 2)
        }
        'TopRight' {
            $x += [math]::Floor($width / 2)
            $width = [math]::Ceiling($width / 2)
            $height = [math]::Floor($height / 2)
        }
        'BottomLeft' {
            $width = [math]::Floor($width / 2)
            $y += [math]::Floor($height / 2)
            $height = [math]::Ceiling($height / 2)
        }
        'BottomRight' {
            $x += [math]::Floor($width / 2)
            $width = [math]::Ceiling($width / 2)
            $y += [math]::Floor($height / 2)
            $height = [math]::Ceiling($height / 2)
        }
        
        # Special
        'Full' {
            # Already set to full screen bounds
        }
        'Maximized' {
            # Same as Full for coordinate purposes
            # Actual maximization happens in Set-WindowPosition
        }
        'Center' {
            # 50% of screen size, centered
            $newWidth = [math]::Floor($width * 0.5)
            $newHeight = [math]::Floor($height * 0.5)
            $x += [math]::Floor(($width - $newWidth) / 2)
            $y += [math]::Floor(($height - $newHeight) / 2)
            $width = $newWidth
            $height = $newHeight
        }
    }
    
    return [PSCustomObject]@{
        X = [int]$x
        Y = [int]$y
        Width = [int]$width
        Height = [int]$height
        Screen = $Screen
        Position = $Position
    }
}

# If script is run directly, show usage example
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`nGet-DockingRegion - Calculate window coordinates for docking regions" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "`nUsage examples:" -ForegroundColor Yellow
    Write-Host "  . .\Get-DockingRegion.ps1" -ForegroundColor White
    Write-Host "  Get-DockingRegion -Screen 0 -Position LeftHalf" -ForegroundColor White
    Write-Host "  Get-DockingRegion -Screen 1 -Position RightTopThird" -ForegroundColor White
    Write-Host "`nRun with -? for full help" -ForegroundColor Gray
}
