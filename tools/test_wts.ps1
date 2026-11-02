Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Wts {
    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSLogoffSession(IntPtr hServer, int sessionId, bool bWait);
}
"@
Write-Output "WTS loaded successfully"
