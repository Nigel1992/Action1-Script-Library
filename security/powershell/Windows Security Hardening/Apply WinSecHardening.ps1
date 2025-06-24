# ================= CONFIGURE OPTIONS HERE =================
$disableWinR = $true                  # Disable Win+R
$disableUSB = $false                 # Disable USB storage
$disableCmdPs = $true               # Disable CMD and PowerShell
$disableWSH = $true                 # Disable Windows Script Host
$disableAutorunUSB = $false        # Disable USB Autorun
$enableDefenderRealtime = $false   # Enable Defender real-time
$disableControlPanel = $false      # Disable Control Panel & Settings
$setWindowsUpdateAuto = $true      # Set Windows Update to auto
$clearTempFilesNow = $true         # Clear %TEMP% files
$createDailyReminder = $false      # Create daily reminder popup
$restartExplorer = $true           # Restart Explorer after applying
# ==========================================================

function Set-RegistryValue($Path, $Name, $Value, $Type = "DWord") {
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

$results = @{}

Write-Host "Starting security hardening script..."

try {
    if ($disableWinR) {
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoRun" 1
        try { Set-RegistryValue "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoRun" 1 } catch {}
        $results["DisableWinR"] = $true
    } else { $results["DisableWinR"] = $null }

    if ($disableUSB) {
        try {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR" -Name "Start" -Value 4
            $results["DisableUSB"] = $true
        } catch {
            Write-Warning "Failed to disable USB: $_"; $results["DisableUSB"] = $false
        }
    } else { $results["DisableUSB"] = $null }

    if ($disableCmdPs) {
        Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\System" "DisableCMD" 1
        $results["DisableCmdPs"] = $true
    } else { $results["DisableCmdPs"] = $null }

    if ($disableWSH) {
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows Script Host\Settings" "Enabled" 0
        $results["DisableWSH"] = $true
    } else { $results["DisableWSH"] = $null }

    if ($disableAutorunUSB) {
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 0xFF
        $results["DisableAutorunUSB"] = $true
    } else { $results["DisableAutorunUSB"] = $null }

    if ($enableDefenderRealtime) {
        try {
            Set-MpPreference -DisableRealtimeMonitoring $false
            $results["EnableDefenderRealtime"] = $true
        } catch {
            Write-Warning "Failed to enable Defender: $_"; $results["EnableDefenderRealtime"] = $false
        }
    } else { $results["EnableDefenderRealtime"] = $null }

    if ($disableControlPanel) {
        Set-RegistryValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoControlPanel" 1
        $results["DisableControlPanel"] = $true
    } else { $results["DisableControlPanel"] = $null }

    if ($setWindowsUpdateAuto) {
        try {
            Set-RegistryValue "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" "AUOptions" 4
            $results["SetWindowsUpdateAuto"] = $true
        } catch {
            Write-Warning "Failed to set Windows Update: $_"; $results["SetWindowsUpdateAuto"] = $false
        }
    } else { $results["SetWindowsUpdateAuto"] = $null }

    if ($clearTempFilesNow) {
        try {
            Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
            $results["ClearTempFilesNow"] = $true
        } catch {
            Write-Warning "Failed to clear TEMP: $_"; $results["ClearTempFilesNow"] = $false
        }
    } else { $results["ClearTempFilesNow"] = $null }

    if ($createDailyReminder) {
        $taskName = "DailySecurityReminder"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-WindowStyle Hidden -Command "[System.Windows.MessageBox]::Show(''Reminder: Be cautious online!'',''Security'')"'
        $trigger = New-ScheduledTaskTrigger -Daily -At 9am
        $principal = New-ScheduledTaskPrincipal -UserId 'BUILTIN\Users' -LogonType Interactive
        try {
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force
            $results["CreateDailyReminder"] = $true
        } catch {
            Write-Warning "Failed to create reminder: $_"; $results["CreateDailyReminder"] = $false
        }
    } else { $results["CreateDailyReminder"] = $null }

} catch {
    Write-Warning "Unexpected error: $_"; exit 1
}

# Restart Explorer if chosen
if ($restartExplorer) {
    Write-Host "Restarting Explorer to apply changes..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

# Summary
$failures = $results.GetEnumerator() | Where-Object { $_.Value -eq $false }
$successes = $results.GetEnumerator() | Where-Object { $_.Value -eq $true }

Write-Host "`n--- Script Result ---"
Write-Host "Succeeded: $($successes.Count), Failed: $($failures.Count)"
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host " - $($_.Name)" }
    exit 1
} else {
    Write-Host "All tasks completed successfully."
    exit 0
}
