<#
.SYNOPSIS
    Checks Kaspersky Antivirus update status and initiates an update if it's older than 24 hours.

.DESCRIPTION
    This script automates the process of checking the last update timestamp of Kaspersky Antivirus
    using Windows Management Instrumentation (WMI/CIM). It then compares this timestamp
    to the current time. If Kaspersky hasn't been updated in the last 24 hours,
    the script will automatically launch the Kaspersky update command-line tool (avp.com)
    to perform an update.

.NOTES
    Author: Nigel Hagen
    Version: 1.1
    Date: June 24, 2025

.EXAMPLE
    To run this script:
    1. Save the code as a .ps1 file (e.g., Update-Kaspersky.ps1).
    2. Open Windows PowerShell.
    3. Navigate to the directory where you saved the script (e.g., cd C:\Scripts).
    4. Execute the script: .\Update-Kaspersky.ps1

    Ensure your PowerShell execution policy allows running scripts. If not, you might need to run:
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
#>

# --- SCRIPT START ---

# Display a clear header to indicate the script's purpose.
Write-Host "--- Checking Kaspersky Update Status ---" -ForegroundColor Cyan

# --- Step 1: Get the Last Update Time from Kaspersky ---
# This command queries Windows' built-in SecurityCenter2 for information about
# installed Antivirus products. We then filter for "Kaspersky" and retrieve its 'timestamp'.
# 'Get-CimInstance' is the modern way to interact with WMI/CIM on Windows.
Write-Host "`nAttempting to retrieve last update timestamp from Kaspersky..."
$lastUpdate = (Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct |
               Where-Object {$_.displayName -like "*Kaspersky*"}).timestamp

# Check if we successfully retrieved a timestamp. If not, it means Kaspersky
# information wasn't found or couldn't be accessed.
if (-not $lastUpdate) {
    Write-Host "ERROR: Could not find Kaspersky update information." -ForegroundColor Red
    Write-Host "       Please ensure Kaspersky Antivirus is installed and running correctly." -ForegroundColor Red
    exit 1 # Exit the script with an error code.
}

Write-Host "Raw timestamp received from Kaspersky: '$lastUpdate'" -ForegroundColor Yellow

# --- Step 2: Convert the Update Time to a Standard Date/Time Object ---
# Kaspersky might report its timestamp in various formats. We need to parse it
# into a standard PowerShell DateTime object so we can perform calculations (like age).
Write-Host "`nAttempting to convert the timestamp to a readable date and time..."

# Define an array of common date/time formats that Kaspersky might use.
# The script will try each one until it successfully parses the timestamp.
$possibleFormats = @(
    "ddd, dd MMM yyyy HH:mm:ss 'GMT'",  # Example: Mon, 17 Feb 2025 21:39:11 GMT
    "dd MMM yyyy HH:mm:ss 'GMT'",      # Example: 17 Feb 2025 21:39:11 GMT
    "ddd, dd MMM yyyy HH:mm:ss",       # Example: Mon, 17 Feb 2025 21:39:11
    "dd MMM yyyy HH:mm:ss",            # Example: 17 Feb 2025 21:39:11
    "yyyy-MM-ddTHH:mm:ssZ",            # ISO 8601 example: 2025-02-17T21:39:11Z
    "yyyy-MM-dd HH:mm:ss",             # Example: 2025-02-17 21:39:11
    "ddd MMM dd HH:mm:ss yyyy"         # Example: Mon Feb 17 21:39:11 2025 (less common)
)

$lastUpdateDateTime = $null # Initialize a variable to store the parsed date/time.

# Loop through each possible format.
foreach ($format in $possibleFormats) {
    try {
        # Try to parse the raw timestamp using the current format.
        # [datetime]::ParseExact requires the string to exactly match the format.
        # [System.Globalization.CultureInfo]::InvariantCulture is used to ensure consistent parsing
        # regardless of the local culture settings (e.g., date separators, month names).
        $lastUpdateDateTime = [datetime]::ParseExact($lastUpdate, $format, [System.Globalization.CultureInfo]::InvariantCulture)
        Write-Host "Successfully parsed timestamp using format: '$format'" -ForegroundColor Green
        break # If successful, we've found the right format, so exit the loop.
    }
    catch {
        # If parsing fails for the current format, an error is caught.
        # We ignore the error and proceed to try the next format.
        # This keeps the script clean and prevents it from stopping prematurely.
    }
}

# If after trying all specific formats, the timestamp still couldn't be parsed,
# try a more general parsing method.
if (-not $lastUpdateDateTime) {
    try {
        # [datetime]::Parse attempts to parse a string into a DateTime object using
        # various common date and time formats.
        $lastUpdateDateTime = [datetime]::Parse($lastUpdate, [System.Globalization.CultureInfo]::InvariantCulture)
        Write-Host "Successfully parsed timestamp using a generic method." -ForegroundColor Green
    }
    catch {
        # If generic parsing also fails, then we cannot understand the timestamp.
        Write-Host "ERROR: Failed to understand Kaspersky's update timestamp: '$lastUpdate'." -ForegroundColor Red
        Write-Host "       The format might be unrecognized. Please check your Kaspersky version or settings." -ForegroundColor Red
        exit 1 # Exit the script due to an unrecoverable error.
    }
}

# --- Step 3: Compare Last Update Time with Current Time ---
# Get the current date and time from the computer.
$currentTime = Get-Date

Write-Host "`nKaspersky last updated on: $($lastUpdateDateTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "Your computer's current time is: $($currentTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White

# Calculate the difference between the current time and the last update time.
# .TotalHours gives the difference in hours, including fractions.
$hoursSinceLastUpdate = ($currentTime - $lastUpdateDateTime).TotalHours

# --- Step 4: Decide Whether to Update Kaspersky ---
# Check if the update is within the last 24 hours.
if ($hoursSinceLastUpdate -lt 24) {
    Write-Host "`nKaspersky is up to date! (Last updated $($hoursSinceLastUpdate.ToString("F1")) hours ago)" -ForegroundColor Green
} else {
    Write-Host "`nKaspersky update is older than 24 hours. Initiating update process..." -ForegroundColor Yellow

    # Dynamically search for avp.com in all Kaspersky Lab subdirectories (handles any version)
    $kasperskyBasePath = "C:\Program Files (x86)\Kaspersky Lab"
    $kasperskyUpdateToolPath = $null
    if (Test-Path $kasperskyBasePath) {
        $avpPaths = Get-ChildItem -Path $kasperskyBasePath -Recurse -Filter "avp.com" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if ($avpPaths -and $avpPaths.Count -gt 0) {
            # Use the first found avp.com (or you could sort and pick the latest if desired)
            $kasperskyUpdateToolPath = $avpPaths | Select-Object -First 1
        }
    }

    # Verify if the Kaspersky update tool executable exists at the found path.
    if (-Not $kasperskyUpdateToolPath -or -Not (Test-Path $kasperskyUpdateToolPath)) {
        Write-Host "ERROR: Kaspersky update executable (avp.com) not found in '$kasperskyBasePath'." -ForegroundColor Red
        Write-Host "       Please verify Kaspersky is installed and update the script if your installation location is different." -ForegroundColor Red
        exit 1 # Exit the script as we can't perform the update.
    }

    Write-Host "Starting Kaspersky update process... This may take a few minutes." -ForegroundColor Gray
    # Start the Kaspersky update process.
    # -FilePath: Specifies the path to the executable (avp.com).
    # -ArgumentList "update": Passes the "update" command to avp.com, telling it to perform an update.
    # -PassThru: Returns a process object, which allows us to get the ExitCode.
    # -Wait: Makes the script wait for the Kaspersky update process to complete before continuing.
    $process = Start-Process -FilePath $kasperskyUpdateToolPath -ArgumentList "update" -PassThru -Wait
    $exitCode = $process.ExitCode # Get the exit code from the completed process.

    # Check the exit code to determine if the update was successful.
    # An exit code of 0 generally indicates success for most applications.
    if ($exitCode -eq 0) {
        Write-Host "Kaspersky updated successfully!" -ForegroundColor Green
    } else {
        Write-Host "Kaspersky update failed with exit code $exitCode." -ForegroundColor Red
        Write-Host "       Please check Kaspersky's logs or interface for more details on the failure." -ForegroundColor Red
    }
}

# Final message to indicate the script has finished its operations.
Write-Host "`n--- Script Finished ---" -ForegroundColor Cyan

# --- SCRIPT END ---
