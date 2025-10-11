# ---------------------------------------------------------------
# Script to disable IPv6 and set OpenDNS on all active adapters
# This version is safe to run via Action1-agent (no pop-ups, no toast)
# Only runs if IPv6 is still enabled or DNS is not set to OpenDNS
# ---------------------------------------------------------------

# ------------------------------
# CONFIGURATION - modify if needed
# ------------------------------
$PrimaryDNS = "208.67.222.222"        # OpenDNS primary DNS
$SecondaryDNS = "208.67.220.220"      # OpenDNS secondary DNS

# ------------------------------
# Get all active network adapters
# ------------------------------
$Adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

# ------------------------------
# Pre-check: determine if any adapter actually needs changes
# This prevents unnecessary execution
# ------------------------------
$NeedsAction = $false

foreach ($Adapter in $Adapters) {
    $InterfaceAlias = $Adapter.Name
    $CurrentDNS = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
    $IPv6Enabled = (Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6).Enabled
    $DNSNotSet = -not ($CurrentDNS.Count -eq 2 -and $CurrentDNS[0] -eq $PrimaryDNS -and $CurrentDNS[1] -eq $SecondaryDNS)

    if ($DNSNotSet -or $IPv6Enabled) {
        $NeedsAction = $true
        break
    }
}

if (-not $NeedsAction) {
    Write-Output "All adapters already have OpenDNS configured and IPv6 is disabled. No action required."
    exit
}

# ------------------------------
# Process each adapter that needs changes
# ------------------------------
foreach ($Adapter in $Adapters) {
    $InterfaceAlias = $Adapter.Name
    $CurrentDNS = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
    $IPv6Enabled = (Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6).Enabled
    $DNSNotSet = -not ($CurrentDNS.Count -eq 2 -and $CurrentDNS[0] -eq $PrimaryDNS -and $CurrentDNS[1] -eq $SecondaryDNS)

    if ($DNSNotSet -or $IPv6Enabled) {
        Write-Output "`nProcessing adapter: $InterfaceAlias"
        Write-Output "IPv6 enabled: $IPv6Enabled, Current DNS: $CurrentDNS"

        # ------------------------------
        # Disable IPv6 binding
        # ------------------------------
        try {
            Disable-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6 -Confirm:$false -ErrorAction Stop
            Write-Output "✅ IPv6 disabled on $InterfaceAlias"
        }
        catch {
            Write-Output ("❌ Failed to disable IPv6 on {0}: {1}" -f $InterfaceAlias, $_)
        }

        # ------------------------------
        # Set DNS to OpenDNS
        # ------------------------------
        try {
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses ($PrimaryDNS, $SecondaryDNS) -ErrorAction Stop
            Write-Output "✅ DNS set to OpenDNS for $InterfaceAlias"
        }
        catch {
            Write-Output ("❌ Failed to set DNS for {0}: {1}" -f $InterfaceAlias, $_)
        }

        # ------------------------------
        # Restart network adapter to apply changes
        # ------------------------------
        try {
            Disable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 2
            Enable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
            Write-Output "✅ Adapter $InterfaceAlias restarted"
        }
        catch {
            Write-Output ("❌ Failed to restart adapter {0}: {1}" -f $InterfaceAlias, $_)
        }

        # ------------------------------
        # Test if internet is reachable
        # Uses ping to 8.8.8.8 until successful
        # ------------------------------
        $InternetUp = $false
        $ping = New-Object System.Net.NetworkInformation.Ping
        Write-Output "🔄 Testing internet connectivity..."

        while (-not $InternetUp) {
            try {
                $reply = $ping.Send("8.8.8.8", 1000)  # 1-second timeout
                if ($reply.Status -eq "Success") {
                    $InternetUp = $true
                } else {
                    Start-Sleep -Seconds 2
                }
            }
            catch {
                Start-Sleep -Seconds 2
            }
        }

        Write-Output "✅ Adapter '$InterfaceAlias' has been restarted and internet is working."
    }
    else {
        Write-Output "`nAdapter $InterfaceAlias already has OpenDNS configured and IPv6 is disabled. No action needed."
    }
}

# ------------------------------
# Flush DNS cache to apply changes
# ------------------------------
Write-Output "`nFlushing DNS cache..."
Clear-DnsClientCache
Write-Output "✅ DNS cache cleared"

Write-Output "`nScript completed."
