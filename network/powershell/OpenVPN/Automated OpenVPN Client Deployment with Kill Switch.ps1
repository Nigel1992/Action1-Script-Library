# =====================================================================
# Automated OpenVPN Client Deployment with Kill Switch
# ---------------------------------------------------------------------
# This script installs OpenVPN, deploys a client config, and sets up a
# Windows firewall kill switch to block all non-VPN traffic.
#
# USAGE:
# 1. Fill in the USER CONFIGURATION section below with your VPN details.
# 2. Run this script as Administrator in PowerShell 7+.
# 3. The script will install OpenVPN, configure the client, and enforce
#    a kill switch via Windows Firewall.
#
# NOTE: Do NOT share your real certificates or private keys publicly!
#       Replace the placeholders below with your own VPN config.
# =====================================================================

# ===================== USER CONFIGURATION ============================
$ConnectOnStartup = $true  # Set to $false to disable auto-connect on startup, will still connect after running the script though.
$OpenVPNUrlBase = "https://openvpn.net/community-downloads/"
$InstallerPath = "$env:TEMP\openvpn_latest.exe"
$OvpnFilePath = "$env:ProgramData\OpenVPN\config\client.ovpn"
$TaskName = "OpenVPNAutoConnect"
$FirewallRuleName = "Block-Non-VPN-Traffic"

# --- BEGIN: USER MUST REPLACE THIS WITH THEIR OWN OVPN CONFIG ---
$OvpnConfigContent = @"
# Example OpenVPN client config
# Replace all placeholders with your actual VPN server and credentials
# Uncomment or adjust options as needed for your provider

client
# dev tun or dev tap depending on your VPN setup
#dev tun
#dev tap

# Protocol: udp or tcp
proto YOUR_PROTOCOL_HERE   # e.g., udp or tcp

# Server address and port
remote YOUR_SERVER_ADDRESS YOUR_PORT_HERE  # e.g., vpn.example.com 1194

# Optional: retry settings
#resolv-retry infinite
#nobind
#float

# Optional: cipher and auth
#ncp-ciphers AES-256-GCM:AES-128-GCM
#auth SHA256

# Optional: compression (only if your server supports it)
#compress

# Optional: keepalive (adjust or comment out if not needed)
#keepalive 15 60

# Optional: TLS settings
#remote-cert-tls server

# Optional: ignore server-pushed routes or DNS
#pull-filter ignore "redirect-private"

<ca>
-----BEGIN CERTIFICATE-----
YOUR_CA_CERTIFICATE_HERE
-----END CERTIFICATE-----
</ca>
<cert>
-----BEGIN CERTIFICATE-----
YOUR_CLIENT_CERTIFICATE_HERE
-----END CERTIFICATE-----
</cert>
<key>
-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY_HERE
-----END PRIVATE KEY-----
</key>
<tls-crypt>
-----BEGIN OpenVPN Static key V1-----
YOUR_TLS_CRYPT_KEY_HERE
-----END OpenVPN Static key V1-----
</tls-crypt>
"@
# --- END: USER MUST REPLACE THIS WITH THEIR OWN OVPN CONFIG ---

function Get-LatestOpenVPNInstaller {
    Write-Host "Getting latest stable OpenVPN installer URL..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/7.0")
        
        # Get the community downloads page
        Write-Host "Downloading page content from $OpenVPNUrlBase"
        $html = $webClient.DownloadString($OpenVPNUrlBase)
        
        # Extract all EXE download links for stable versions (excluding alpha/beta/rc)
        $pattern = "href=`"(https://[^`"]*?openvpn-install-\d+\.\d+\.\d+-I\d+-Win10\.exe)`""
        Write-Host "Using pattern: $pattern"
        $matches = [regex]::Matches($html, $pattern)
        
        Write-Host "Found $($matches.Count) matches"
        $matches | ForEach-Object {
            Write-Host "Match: $($_.Groups[1].Value)"
        }
        
        if (-not $matches -or $matches.Count -eq 0) {
            throw "No installer links found matching pattern!"
        }
        
        # Get all version numbers and sort them
        $versions = $matches | ForEach-Object {
            $url = $_.Groups[1].Value
            if ($url -match "openvpn-install-(\d+\.\d+\.\d+)-I(\d+)-Win10\.exe") {
                [PSCustomObject]@{
                    Version = [version]$Matches[1]
                    BuildNumber = [int]$Matches[2]
                    FullVersion = "$($Matches[1])-I$($Matches[2])"
                    Url = $url
                }
            }
        } | Sort-Object Version, BuildNumber -Descending
        
        # Get the latest version
        $latest = $versions | Select-Object -First 1
        
        if (-not $latest) {
            throw "Could not determine latest version!"
        }

        Write-Host "Latest stable version found: $($latest.FullVersion)"
        Write-Host "Download URL: $($latest.Url)"
        return $latest.Url
    }
    catch {
        throw "Failed to get installer URL: $_"
    }
}

function Install-OpenVPN {
    # Check if OpenVPN is already installed by looking for the executable
    $openvpnPath = "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"
    if (Test-Path $openvpnPath) {
        Write-Host "OpenVPN is already installed at $openvpnPath"
        return $true
    }

    $installerUrl = Get-LatestOpenVPNInstaller

    Write-Host "Downloading OpenVPN installer..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell/7.0")
        $webClient.DownloadFile($installerUrl, $InstallerPath)
        
        # Verify the download
        if (-not (Test-Path $InstallerPath)) {
            throw "Downloaded file not found!"
        }
        
        $fileInfo = Get-Item $InstallerPath
        if ($fileInfo.Length -lt 1MB) {
            throw "Downloaded file is too small, possibly corrupted!"
        }

        Write-Host "Download completed successfully. File size: $([Math]::Round($fileInfo.Length / 1MB, 2)) MB"
        
        Write-Host "Installing OpenVPN silently..."
        
        # Check if running with admin privileges
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host "Requesting elevation for silent installation..."
            $proc = Start-Process $InstallerPath -ArgumentList "/S" -Verb RunAs -Wait -PassThru
        } else {
            $proc = Start-Process $InstallerPath -ArgumentList "/S" -Wait -PassThru
        }
        
        $exitCode = $proc.ExitCode
        if ($exitCode -ne 0) {
            throw "OpenVPN silent installation failed with exit code $exitCode"
        }

        Write-Host "OpenVPN installed successfully."
        
        # Clean up the installer
        Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
        
        # Wait for services to start
        Start-Sleep -Seconds 5
        
        return $true
    }
    catch {
        Write-Error "Installation failed: $_"
        if (Test-Path $InstallerPath) {
            Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Write-OvpnConfig {
    Write-Host "Writing OpenVPN configuration..."

    # The user's server pushes 'block-outside-dns', which conflicts with this script's firewall management.
    # The client config also contains a 'pull-filter' that can interfere with receiving the pushed DNS server.
    # This function removes the bad filter and adds a new one to ignore the conflicting firewall command from the server.
    
    $tempConfig = $OvpnConfigContent -replace '(?m)^\s*pull-filter\s+ignore\s+"redirect-private".*$', ''
    Write-Host "Removed 'pull-filter ignore ""redirect-private""' from client config."

    $enhancedConfig = $tempConfig.Trim() + @"

# --- Settings Added By Script ---
# Ignore the server's request to manage the Windows Firewall, as this script handles it completely.
pull-filter ignore "block-outside-dns"
"@

    $configDir = Split-Path $OvpnFilePath
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    $enhancedConfig | Set-Content -Path $OvpnFilePath -Encoding ASCII
    Write-Host "Config saved to $OvpnFilePath. It will now let this script manage all firewall rules."
}

function Set-VPNOnlyFirewall {
    param(
        [bool]$Enable
    )
    
    Write-Host "Configuring firewall for VPN-only access..."
    try {
        # Remove existing rules if they exist
        Get-NetFirewallRule -Name "$FirewallRuleName*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule

        if ($Enable) {
            # Set default outbound action to Block for a robust kill switch
            Write-Host "Setting default outbound firewall action to BLOCK."
            Set-NetFirewallProfile -Profile Private,Public,Domain -DefaultOutboundAction Block

            # Allow the OpenVPN program itself, which is more reliable than a port-based rule
            $openvpnExe = "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"
            if (Test-Path $openvpnExe) {
                New-NetFirewallRule -Name "$FirewallRuleName-AllowOpenVPN" `
                    -DisplayName "Allow OpenVPN Executable" `
                    -Direction Outbound `
                    -Program $openvpnExe `
                    -Action Allow | Out-Null
            } else {
                throw "OpenVPN executable not found at $openvpnExe. Cannot create firewall rule."
            }

            # Allow DNS (temporarily)
            New-NetFirewallRule -Name "$FirewallRuleName-DNS" `
                -DisplayName "Allow DNS" `
                -Direction Outbound `
                -Action Allow `
                -Profile Any `
                -Protocol UDP `
                -RemotePort 53 | Out-Null

            # Allow DHCP
            New-NetFirewallRule -Name "$FirewallRuleName-DHCP" `
                -DisplayName "Allow DHCP" `
                -Direction Outbound `
                -Action Allow `
                -Profile Any `
                -Protocol UDP `
                -LocalPort 68 `
                -RemotePort 67 | Out-Null

            # Allow ICMP for connection test (temporarily)
            New-NetFirewallRule -Name "$FirewallRuleName-ICMP" `
                -DisplayName "Allow ICMP for Connection Test" `
                -Direction Outbound `
                -Action Allow `
                -Profile Any `
                -Protocol ICMPv4 | Out-Null

            Write-Host "Firewall configured to only allow essential traffic."
        } else {
            # Restore default outbound action
            Write-Host "Restoring default outbound firewall action to ALLOW."
            Set-NetFirewallProfile -Profile Private,Public,Domain -DefaultOutboundAction Allow
            Write-Host "Removing VPN-only firewall rules..."
        }
    }
    catch {
        Write-Error "Failed to configure firewall: $_"
        throw
    }
}

function Get-VPNAdapter {
    param(
        [int]$RetryCount = 30,
        [int]$RetryInterval = 2
    )

    Write-Host "Looking for VPN adapter..."
    
    # List of possible TAP adapter names
    $adapterPatterns = @(
        "*TAP-Windows*",
        "*TAP-Windows Adapter V9*",
        "*OpenVPN TAP-Windows6*",
        "*OpenVPN Adapter*",
        "*TAP-ProtonVPN Windows Adapter V9*"
    )
    
    for ($i = 0; $i -lt $RetryCount; $i++) {
        foreach ($pattern in $adapterPatterns) {
            $adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like $pattern } | Select-Object -First 1
            if ($adapter) {
                Write-Host "Found VPN adapter: $($adapter.InterfaceDescription)"
                return $adapter
            }
        }
        
        if ($i -lt $RetryCount - 1) {
            Write-Host "VPN adapter not found, waiting $RetryInterval seconds... (Attempt $($i + 1)/$RetryCount)"
            Start-Sleep -Seconds $RetryInterval
        }
    }
    
    return $null
}

function Test-VPNConnection {
    param(
        [int]$TimeoutSeconds = 60
    )
    
    Write-Host "Testing VPN connection..."
    $startTime = Get-Date
    $connected = $false
    
    while (-not $connected -and ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 2
        
        # Check if OpenVPN process is running
        $vpnProcess = Get-Process -Name openvpn -ErrorAction SilentlyContinue
        if (-not $vpnProcess) {
            Write-Host "OpenVPN process not running..."
            continue
        }
        
        # Check if TAP adapter is present and has an IP
        $vpnAdapter = Get-VPNAdapter
        if (-not $vpnAdapter) {
            Write-Host "Waiting for VPN adapter to become available..."
            continue
        }
        
        $vpnIPs = Get-NetIPAddress -InterfaceIndex $vpnAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if (-not $vpnIPs) {
            Write-Host "Waiting for IP address assignment..."
            continue
        }
        
        # Use the first available IP address
        $vpnIP = ($vpnIPs | Select-Object -First 1).IPAddress
        Write-Host "VPN adapter found with IP: $vpnIP"
        
        # Try to ping through VPN using the adapter's IP as a source.
        # This is more compatible across PowerShell versions than Test-NetConnection -InterfaceIndex
        $pingResult = ping.exe -n 1 -S $vpnIP 8.8.8.8
        if ($pingResult -match "Reply from") {
            $connected = $true
            Write-Host "VPN connection verified!"
            break
        }
        
        Write-Host "Waiting for VPN connection to establish..."
    }
    
    if (-not $connected) {
        Write-Host "VPN connection test failed after $TimeoutSeconds seconds"
        # Collect diagnostic information
        Write-Host "`nDiagnostic Information:"
        Write-Host "------------------------"
        Write-Host "OpenVPN Process Status:"
        Get-Process -Name openvpn -ErrorAction SilentlyContinue | Format-Table -AutoSize
        
        Write-Host "`nNetwork Adapters:"
        Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like "*TAP*" -or $_.InterfaceDescription -like "*OpenVPN*" } | Format-Table -AutoSize
        
        Write-Host "`nIP Configurations:"
        Get-NetIPConfiguration -IncludeHidden | Format-Table -AutoSize
    }
    
    return $connected
}

function Start-VPNConnection {
    Write-Host "Starting VPN connection..."
    $openvpnExe = "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"
    if (-not (Test-Path $openvpnExe)) {
        throw "OpenVPN executable not found at $openvpnExe"
    }

    # Kill any existing OpenVPN processes
    Stop-Process -Name openvpn -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Enable VPN-only firewall
    Set-VPNOnlyFirewall -Enable $true

    # Start OpenVPN with elevation if needed
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Requesting elevation to start VPN..."
        $arguments = "/c `"$openvpnExe`" --config `"$OvpnFilePath`""
        $proc = Start-Process "cmd.exe" -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
    } else {
        Start-Process -FilePath $openvpnExe -ArgumentList "--config `"$OvpnFilePath`"" -WindowStyle Hidden
    }

    # Wait a bit for the process to start
    Start-Sleep -Seconds 5

    # Test the connection with increased timeout
    $connected = Test-VPNConnection -TimeoutSeconds 60
    if (-not $connected) {
        Set-VPNOnlyFirewall -Enable $false
        Write-Error "Failed to establish VPN connection within timeout period"
        return $false
    }

    # Connection is successful, now configure the adapter AND OPEN THE FIREWALL FOR IT.
    Write-Host "VPN connected. Configuring VPN network adapter and firewall..."
    $vpnAdapter = Get-VPNAdapter
    if ($vpnAdapter) {
        try {
            Write-Host "Setting VPN network category to 'Private'..."
            Set-NetConnectionProfile -InterfaceIndex $vpnAdapter.ifIndex -NetworkCategory Private
            
            Write-Host "Setting VPN interface metric to 1 to prioritize it..."
            Set-NetIPInterface -InterfaceIndex $vpnAdapter.ifIndex -InterfaceMetric 1
            
            # THIS IS THE CRUCIAL FIX: Create the rule to allow traffic through the VPN tunnel.
            Write-Host "Creating firewall rule to allow all outbound traffic on the VPN interface..."
            New-NetFirewallRule -Name "$FirewallRuleName-AllowVPNInterface" `
                -DisplayName "Allow All Outbound on VPN Interface" `
                -Direction Outbound `
                -Action Allow `
                -InterfaceAlias $vpnAdapter.Name | Out-Null

            Write-Host "Successfully configured VPN adapter and firewall."
        }
        catch {
            Write-Warning "Could not fully configure the VPN adapter or firewall. Internet may not work. Error: $_"
        }
    } else {
        Write-Warning "Could not find VPN adapter to configure."
    }

    # Remove temporary rules now that VPN is established
    Write-Host "Securing firewall by removing temporary rules..."
    Remove-NetFirewallRule -Name "$FirewallRuleName-DNS" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -Name "$FirewallRuleName-ICMP" -ErrorAction SilentlyContinue

    Write-Host "VPN connection established and secured."
    return $true
}

function Stop-VPNConnection {
    Write-Host "Stopping VPN connection..."
    
    # Disable VPN-only firewall
    Set-VPNOnlyFirewall -Enable $false
    
    # Stop OpenVPN processes
    $vpnProcesses = Get-Process -Name openvpn -ErrorAction SilentlyContinue
    if ($vpnProcesses) {
        $vpnProcesses | Stop-Process -Force
        Write-Host "VPN connection stopped."
    } else {
        Write-Host "No VPN connection found."
    }
}

function Cleanup-StaleAdapters {
    Write-Host "Checking for stale OpenVPN network adapters..."
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warning "Administrator privileges required to clean up network adapters. Skipping."
        return
    }

    try {
        # Use the same adapter patterns as Get-VPNAdapter function for consistency
        $adapterPatterns = @(
            "*TAP-Windows*",
            "*TAP-Windows Adapter V9*",
            "*OpenVPN TAP-Windows6*",
            "*OpenVPN Adapter*",
            "*TAP-ProtonVPN Windows Adapter V9*"
        )
        
        # Find all OpenVPN TAP adapters using the same patterns
        $tapAdapters = @()
        foreach ($pattern in $adapterPatterns) {
            $adapters = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceDescription -like $pattern }
            $tapAdapters += $adapters
        }
        
        # Remove duplicates based on InterfaceIndex
        $tapAdapters = $tapAdapters | Sort-Object InterfaceIndex -Unique
        
        if ($tapAdapters.Count -le 1) {
            Write-Host "No stale OpenVPN adapters found."
            return
        }

        Write-Host "Found $($tapAdapters.Count) OpenVPN TAP adapters. Cleaning up stale adapters..."
        
        # Keep the first one, remove the rest
        $adaptersToRemove = $tapAdapters | Select-Object -Skip 1
        
        foreach ($adapter in $adaptersToRemove) {
            Write-Host "Removing adapter: $($adapter.Name) ($($adapter.InterfaceDescription))"
            $pnpDevice = Get-PnpDevice -FriendlyName $adapter.InterfaceDescription -Class 'Net' | Where-Object { $_.InstanceId -eq $adapter.PnpDeviceID }
            if ($pnpDevice) {
                Uninstall-PnpDevice -InstanceId $pnpDevice.InstanceId -Confirm:$false -Force
            } else {
                Write-Warning "Could not find PnP device for adapter $($adapter.Name) to uninstall."
            }
        }
        
        Write-Host "Adapter cleanup complete."
        Start-Sleep -Seconds 3 # Give a moment for changes to settle
    }
    catch {
        Write-Warning "An error occurred during adapter cleanup: $_. This may not be critical."
    }
}

function Create-AutoStartTask {
    Write-Host "Creating Scheduled Task for OpenVPN auto-start..."

    # Check if task exists, delete to refresh
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    $openvpnExe = "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"

    $action = New-ScheduledTaskAction -Execute $openvpnExe -Argument "--config `"$OvpnFilePath`""
    
    # Change trigger to computer startup for RMM deployment reliability
    $trigger = New-ScheduledTaskTrigger -AtStartup
    
    # Run the task as the SYSTEM account, which is robust and avoids user context issues.
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit 0
    
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskName $TaskName -InputObject $task

    Write-Host "Scheduled Task created to run as SYSTEM at startup."
}

function Remove-AutoStartTask {
    Write-Host "Removing Scheduled Task if exists..."
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Scheduled Task removed."
    } else {
        Write-Host "No Scheduled Task found."
    }
}

# Main Logic
try {
    $installResult = Install-OpenVPN
    Write-OvpnConfig

    if ($ConnectOnStartup) {
        Cleanup-StaleAdapters
        Write-Host "Attempting to connect VPN..."
        $connected = Start-VPNConnection
        if ($connected) {
            Create-AutoStartTask
            Write-Output "VPN Connected Successfully"
        } else {
            Write-Error "VPN Failed to Connect. Please check the logs above for diagnostic information."
        }
    } else {
        Stop-VPNConnection
        Remove-AutoStartTask
        Write-Output "VPN Disconnected and auto-start disabled."
    }
} catch {
    Write-Error "A critical error occurred: $_"
    exit 1
}
