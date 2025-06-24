# ================= RESET OPTIONS =================
$restartExplorer = $true  # Set to $true to restart Explorer after restoring defaults
# =================================================

Write-Host "Resetting system settings to Windows defaults..."

function Remove-RegistryValueIfExists($Path, $Name) {
    if (Test-Path $Path) {
        try {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to remove `${Name}` from `${Path}`: $_"
        }
    }
}


# Win+R (NoRun)
Remove-RegistryValueIfExists "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoRun"
Remove-RegistryValueIfExists "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoRun"

# USB storage
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR" -Name "Start" -Value 3
} catch { Write-Warning "Failed to restore USB: $_" }

# CMD and PowerShell
Remove-RegistryValueIfExists "HKCU:\Software\Policies\Microsoft\Windows\System" "DisableCMD"

# Windows Script Host
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows Script Host\Settings" -Name "Enabled" -Value 1
} catch { Write-Warning "Failed to enable WSH: $_" }

# Autorun
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 0x91

# Control Panel
Remove-RegistryValueIfExists "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoControlPanel"

# Windows Update
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 3
} catch { Write-Warning "Failed to reset Windows Update: $_" }

# Defender real-time protection
try {
    Set-MpPreference -DisableRealtimeMonitoring $false
} catch { Write-Warning "Failed to re-enable Defender: $_" }

# Remove reminder task
try {
    Unregister-ScheduledTask -TaskName "DailySecurityReminder" -Confirm:$false -ErrorAction SilentlyContinue
} catch { Write-Warning "Failed to remove reminder: $_" }

# Restart Explorer if needed
if ($restartExplorer) {
    Write-Host "Restarting Explorer to apply settings..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

Write-Host "`n✅ All settings have been restored to default. A logoff or reboot may still be needed for some policies."
exit 0
