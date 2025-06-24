<#
.SYNOPSIS
    Set DNS servers on all active network adapters.

.DESCRIPTION
    This script finds all currently active (connected) network adapters
    and sets their DNS servers to OpenDNS using PowerShell.

.NOTES
    Run as Administrator.
    Modify DNS values below if you want to use different DNS providers.
#>

# ========================
# 🔧 DNS Servers
# ========================
$PrimaryDNS = "208.67.222.222"     # OpenDNS Primary
$SecondaryDNS = "208.67.220.220"   # OpenDNS Secondary

# ================================
# 🔍 Get Active Network Adapters
# ================================
Write-Output "`n🔍 Fetching active network adapters..."
$Adapters = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.NetConnectionStatus -eq 2 }

if ($Adapters.Count -eq 0) {
    Write-Output "❌ No active network adapters found. Exiting..."
    exit 1
}

# ================================
# ⚙️ Set DNS for Each Adapter
# ================================
foreach ($Adapter in $Adapters) {
    $InterfaceAlias = $Adapter.NetConnectionID

    if ($InterfaceAlias) {
        Write-Output "`n🔧 Configuring adapter: $InterfaceAlias"
        Write-Output " - Adapter Name: $($Adapter.Name)"
        Write-Output " - MAC Address: $($Adapter.MACAddress)"
        
        try {
            # Apply OpenDNS servers
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses ($PrimaryDNS, $SecondaryDNS) -ErrorAction Stop
            Write-Output " ✅ DNS set to OpenDNS for $InterfaceAlias"
        } catch {
            Write-Output " ❌ Failed to set DNS for $InterfaceAlias"
            Write-Output " ⚠️ Error Details: $_"
        }
    }
    else {
        Write-Output " ⚠️ Skipping adapter (no InterfaceAlias)"
    }
}

Write-Output "`n✅ DNS configuration complete for all active adapters."
