# =====================================================================
# Complete OpenVPN Removal and System Reset
# ---------------------------------------------------------------------
# This script undoes all actions performed by the OpenVPN deployment script.
# It stops the VPN, removes firewall rules, deletes the scheduled task,
# uninstalls OpenVPN, and removes TAP adapters.
#
# USAGE:
# 1. Run this script as Administrator in PowerShell 7+.
# 2. If you changed any names/paths in the deployment script, update the
#    variables in the USER CONFIGURATION section below to match.
# 3. The script will attempt to clean up all OpenVPN-related changes.
#
# NOTE: No private information is stored in this script. Adjust only the
#       variables below if your setup differs from the default.
# =====================================================================

# ===================== USER CONFIGURATION ============================
$TaskName = "OpenVPNAutoConnect"           # Scheduled task name (match your deployment script)
$FirewallRuleName = "Block-Non-VPN-Traffic" # Firewall rule name prefix (match your deployment script)
$OvpnConfigDir = "$env:ProgramData\OpenVPN" # OpenVPN config directory
$OpenVPNUninstallPath = "$env:ProgramFiles\OpenVPN\Uninstall.exe" # OpenVPN uninstaller path
# =====================================================================

#Requires -RunAsAdministrator

<#
.SYNOPSIS
    This script undoes all actions performed by the OpenVPN.ps1 installation script.
    It stops the VPN, removes firewall rules, deletes the scheduled task, and uninstalls OpenVPN.
.DESCRIPTION
    This script is designed to safely revert the system to its state before the OpenVPN script was run.
    It requires administrative privileges to perform these actions.
#>

# Configuration - These should match the names used in the main script.
$TaskName = "OpenVPNAutoConnect"
$FirewallRuleName = "Block-Non-VPN-Traffic"
$OvpnConfigDir = "$env:ProgramData\OpenVPN"
$OpenVPNUninstallPath = "$env:ProgramFiles\OpenVPN\Uninstall.exe"

# --- Main Logic ---

Write-Host "Starting full cleanup of OpenVPN installation and configuration..." -ForegroundColor Yellow

# 1. Stop any running OpenVPN processes
Write-Host "Step 1: Stopping OpenVPN processes..."
$vpnProcesses = Get-Process -Name "openvpn" -ErrorAction SilentlyContinue
if ($vpnProcesses) {
    $vpnProcesses | Stop-Process -Force
    Write-Host "Successfully stopped OpenVPN processes."
} else {
    Write-Host "No running OpenVPN processes found."
}
Start-Sleep -Seconds 2

# 2. Remove the Scheduled Task for auto-start
Write-Host "Step 2: Removing Scheduled Task..."
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Successfully removed the '$TaskName' scheduled task."
} else {
    Write-Host "No scheduled task named '$TaskName' found."
}

# 3. Reset Windows Firewall to default and remove custom rules
Write-Host "Step 3: Resetting Windows Firewall..."
try {
    # Restore default outbound action to Allow (the Windows default)
    Write-Host "Restoring default outbound firewall action to 'Allow' for all profiles."
    Set-NetFirewallProfile -Profile Private,Public,Domain -DefaultOutboundAction Allow

    # Find and delete all rules created by the script
    $rules = Get-NetFirewallRule -Name "$FirewallRuleName*" -ErrorAction SilentlyContinue
    if ($rules) {
        Write-Host "Found and removing $($rules.Count) custom firewall rules..."
        $rules | Remove-NetFirewallRule
        Write-Host "Successfully removed all firewall rules starting with '$FirewallRuleName'."
    } else {
        Write-Host "No firewall rules starting with '$FirewallRuleName' found."
    }
}
catch {
    Write-Warning "An error occurred while resetting the firewall: $_"
}

# 4. Delete the OpenVPN configuration directory
Write-Host "Step 4: Deleting OpenVPN configuration directory..."
if (Test-Path $OvpnConfigDir) {
    Remove-Item -Path $OvpnConfigDir -Recurse -Force
    Write-Host "Successfully deleted directory: $OvpnConfigDir"
} else {
    Write-Host "Configuration directory not found at $OvpnConfigDir."
}

# 5. Uninstall OpenVPN application
Write-Host "Step 5: Uninstalling OpenVPN application..."
if (Test-Path $OpenVPNUninstallPath) {
    Write-Host "Found uninstaller. Starting silent uninstallation..."
    $proc = Start-Process $OpenVPNUninstallPath -ArgumentList "/S" -Wait -PassThru
    if ($proc.ExitCode -eq 0) {
        Write-Host "OpenVPN uninstalled successfully."
    } else {
        Write-Warning "OpenVPN uninstaller finished with a non-zero exit code: $($proc.ExitCode). Manual check may be required."
    }
} else {
    Write-Host "OpenVPN uninstaller not found at '$OpenVPNUninstallPath'. The application may have already been removed."
}

# 6. Remove all OpenVPN TAP adapters
Write-Host "Step 6: Removing all OpenVPN TAP adapters..."
try {
    # Use comprehensive adapter patterns to catch all possible OpenVPN TAP adapters
    $adapterPatterns = @(
        "*TAP-Windows*",
        "*TAP-Windows Adapter V9*",
        "*OpenVPN TAP-Windows6*",
        "*OpenVPN Adapter*",
        "*TAP-ProtonVPN Windows Adapter V9*"
    )
    
    # Find all OpenVPN TAP adapters using the patterns
    $tapAdapters = @()
    foreach ($pattern in $adapterPatterns) {
        $adapters = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like $pattern }
        $tapAdapters += $adapters
    }
    
    # Remove duplicates based on InterfaceIndex
    $tapAdapters = $tapAdapters | Sort-Object InterfaceIndex -Unique
    
    if ($tapAdapters) {
        Write-Host "Found $($tapAdapters.Count) OpenVPN TAP adapters. Removing all..."
        
        foreach ($adapter in $tapAdapters) {
            Write-Host "Attempting to remove adapter: $($adapter.Name) - $($adapter.InterfaceDescription)"
            # Get the PnP device associated with the network adapter
            $pnpDevice = Get-PnpDevice -InstanceId $adapter.PnpDeviceID -ErrorAction SilentlyContinue
            
            if ($pnpDevice) {
                # Uninstall the device
                Write-Host "  - Found PnP Device. Uninstalling..."
                Uninstall-PnpDevice -InstanceId $pnpDevice.InstanceId -Confirm:$false -Force
                Write-Host "  - Uninstall command sent."
            } else {
                Write-Warning "  - Could not find the corresponding PnP device for this adapter. It may need to be removed manually from Device Manager (View -> Show hidden devices)."
            }
        }
        Write-Host "Adapter removal process complete. Giving the system a moment to catch up..."
        Start-Sleep -Seconds 5
    } else {
        Write-Host "No OpenVPN TAP adapters were found."
    }
}
catch {
    Write-Warning "An error occurred during adapter cleanup: $_. Manual removal from Device Manager may be required."
}

# 7. Final check for remaining TAP adapters (informational)
Write-Host "Step 7: Final check for any remaining TAP adapters..."
$remainingTapAdapters = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like "*TAP*" -or $_.InterfaceDescription -like "*OpenVPN*" }
if ($remainingTapAdapters) {
    Write-Warning "One or more TAP network adapters are still present. This can happen if they were in use or if a reboot is required."
    Write-Warning "They can usually be manually removed from Device Manager if desired (View -> Show hidden devices)."
    $remainingTapAdapters | Format-Table Name, InterfaceDescription -AutoSize
} else {
    Write-Host "No remaining TAP adapters found."
}


Write-Host ""
Write-Host "Cleanup complete." -ForegroundColor Green 