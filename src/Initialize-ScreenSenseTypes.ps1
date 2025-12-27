# Initialize-ScreenSenseTypes.ps1
# Ensures Win32 API types are loaded for ScreenSense module

# Load WindowEnumerator type for EnumWindows functionality
if (-not ([System.Management.Automation.PSTypeName]'WindowEnumerator').Type) {
    $windowEnumeratorCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class WindowEnumerator {
    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    
    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    
    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    
    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        
        public int Width { get { return Right - Left; } }
        public int Height { get { return Bottom - Top; } }
        public int Area { get { return Width * Height; } }
    }
    
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    private const uint GW_OWNER = 4;
    
    public static List<IntPtr> GetWindowsForProcess(int processId) {
        List<IntPtr> windows = new List<IntPtr>();
        
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
            uint pid = 0;
            GetWindowThreadProcessId(hWnd, out pid);
            
            if (pid == processId) {
                // Filter: must be visible
                if (!IsWindowVisible(hWnd)) return true;
                
                // Filter: must be top-level (no owner)
                IntPtr owner = GetWindow(hWnd, GW_OWNER);
                if (owner != IntPtr.Zero) return true;
                
                // Filter: must have reasonable size
                RECT rect;
                if (GetWindowRect(hWnd, out rect)) {
                    if (rect.Width < 50 || rect.Height < 50) return true;
                }
                
                windows.Add(hWnd);
            }
            
            return true;
        }, IntPtr.Zero);
        
        // If multiple windows found, prefer the largest
        if (windows.Count > 1) {
            windows.Sort((a, b) => {
                RECT rectA, rectB;
                GetWindowRect(a, out rectA);
                GetWindowRect(b, out rectB);
                return rectB.Area.CompareTo(rectA.Area);
            });
        }
        
        return windows;
    }
}
'@
    Add-Type -TypeDefinition $windowEnumeratorCode
}

# Load ScreenSense.User32 type for window positioning
if (-not ([System.Management.Automation.PSTypeName]'ScreenSense.User32').Type) {
    $screenSenseUser32Code = @'
using System;
using System.Runtime.InteropServices;

namespace ScreenSense {
    public class User32 {
        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsZoomed(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    }
}
'@
    Add-Type -TypeDefinition $screenSenseUser32Code
}

Write-Verbose "ScreenSense Win32 types loaded successfully"
