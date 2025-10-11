 # ---------------------------------------------------------------
# OpenDNS servers
# ---------------------------------------------------------------
$PrimaryDNS = "208.67.222.222"
$SecondaryDNS = "208.67.220.220"

# Active adapters
$Adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

# Controleer eerst of er überhaupt iets aangepast hoeft te worden
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
    Write-Output "Alle adapters hebben al OpenDNS ingesteld en IPv6 is uit. Geen actie nodig."
    exit
}

# ---------------------------------------------------------------
# Verwerking van adapters die actie nodig hebben
# ---------------------------------------------------------------
foreach ($Adapter in $Adapters) {
    $InterfaceAlias = $Adapter.Name
    $CurrentDNS = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
    $IPv6Enabled = (Get-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6).Enabled
    $DNSNotSet = -not ($CurrentDNS.Count -eq 2 -and $CurrentDNS[0] -eq $PrimaryDNS -and $CurrentDNS[1] -eq $SecondaryDNS)

    if ($DNSNotSet -or $IPv6Enabled) {
        Write-Output "`nProcessing adapter: $InterfaceAlias"
        Write-Output "IPv6 enabled: $IPv6Enabled, Current DNS: $CurrentDNS"

        # IPv6 uitschakelen
        try {
            Disable-NetAdapterBinding -Name $InterfaceAlias -ComponentID ms_tcpip6 -Confirm:$false -ErrorAction Stop
            Write-Output "✅ IPv6 disabled on $InterfaceAlias"
        }
        catch {
            Write-Output ("❌ Failed to disable IPv6 on {0}: {1}" -f $InterfaceAlias, $_)
        }

        # Stel OpenDNS in
        try {
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses ($PrimaryDNS, $SecondaryDNS) -ErrorAction Stop
            Write-Output "✅ DNS set to OpenDNS for $InterfaceAlias"
        }
        catch {
            Write-Output ("❌ Failed to set DNS for {0}: {1}" -f $InterfaceAlias, $_)
        }

        # Herstart adapter
        try {
            Disable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 2
            Enable-NetAdapter -Name $InterfaceAlias -Confirm:$false -ErrorAction Stop
            Write-Output "✅ Adapter $InterfaceAlias restarted"
        }
        catch {
            Write-Output ("❌ Failed to restart adapter {0}: {1}" -f $InterfaceAlias, $_)
        }

        # Test of internet werkt veilig
        $InternetUp = $false
        $ping = New-Object System.Net.NetworkInformation.Ping
        Write-Output "🔄 Testing internet connectivity..."

        while (-not $InternetUp) {
            try {
                $reply = $ping.Send("8.8.8.8", 1000)
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

        Write-Output "✅ Adapter '$InterfaceAlias' is opnieuw gestart en internet werkt weer."
    }
    else {
        Write-Output "`nAdapter $InterfaceAlias heeft al OpenDNS ingesteld en IPv6 is uit. Geen actie nodig."
    }
}

# DNS cache flushen
Write-Output "`nFlushing DNS cache..."
Clear-DnsClientCache
Write-Output "✅ DNS cache cleared"

Write-Output "`nScript voltooid."
