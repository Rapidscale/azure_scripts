# Script to configure DNS on a Windows Server without the Domain Role
# Usage: setup-dns.ps1 -Server -Client -DNS1 "8.8.8.8" -DNS2 "1.1.1.1"
#
# Configure Parameters
# If -Server is specified, the script will configure the server as a DNS server and configure the specified DNS servers as forwarders
# If -Client is specified, the script will configure the client to use the specified DNS servers
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Server,
    [Parameter(Mandatory=$false)]
    [switch]$Client,
    [Parameter(Mandatory=$true)]
    [string]$DNS1,
    [Parameter(Mandatory=$true)]
    [string]$DNS2
)
# Set Strict Mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Logging
Function Write-ProgressLog {
    $Message = $args[0]
    Write-EventLog -LogName Application -Source $EventSource -EntryType Information -EventId 1 -Message $Message
}
Function Write-VerboseLog {
    $Message = $args[0]
    Write-Verbose $Message
    Write-ProgressLog $Message
}
Function Write-HostLog {
    $Message = $args[0]
    Write-Output $Message
    Write-ProgressLog $Message
}
$EventSource = $MyInvocation.MyCommand.Name
If (-Not $EventSource) {
    $EventSource = "Powershell CLI"
}
If ([System.Diagnostics.EventLog]::Exists('Application') -eq $False -or [System.Diagnostics.EventLog]::SourceExists($EventSource) -eq $False) {
    New-EventLog -LogName Application -Source $EventSource
}
# Validate Parameters
if ($Server -and $Client) {
    Write-HostLog "Cannot specify both -Server and -Client"
    exit 1
}
if (-Not $Server -and -Not $Client) {
    Write-HostLog "Must specify either -Server or -Client"
    exit 1
}
# Identify Ethernet adapter name
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.InterfaceDescription -like "*Ethernet*"}
# Set the DNS servers
if ($Server) {
    # Configure DNS server
    Write-HostLog "Configuring DNS server"
    # Check if DNS server role is installed
    if (-Not (Get-WindowsFeature -Name "DNS").Installed) {
        Write-HostLog "DNS server role is not installed, installing it now"
        Install-WindowsFeature -Name "DNS" -IncludeManagementTools
    }
    try {
        Write-HostLog "Configuring Interface DNS"
        Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses 127.0.0.1,$DNS1,$DNS2
    } catch {
        Write-HostLog "Failed to configure DNS server"
        exit 1
    }
    # Configure DNS forwarders
    try {
        Write-HostLog "Configuring DNS forwarders"
        Add-DnsServerForwarder -IPAddress $DNS1,$DNS2
    } catch {
        Write-HostLog "Failed to configure DNS forwarders"
        exit 1
    }
} else {
    # Configure DNS client
    Write-HostLog "Configuring DNS client"
    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $DNS1,$DNS2
}
# Flush DNS
Write-HostLog "Flushing DNS cache"
try {
    ipconfig /flushdns | Out-Null
} catch {
    Write-HostLog "Failed to flush DNS cache"
    exit 1
}
# Verify DNS resolution
$NetTarget = "www.google.com"
$timeout = 1 # Hours
$timer = [Diagnostics.Stopwatch]::StartNew()
do {  
    if ($timer.Elapsed.TotalHours -ge $timeout) {
        Write-HostLog "DNS failed to resolve"
        Exit 1
    }
    Write-HostLog "Waiting for DNS to resolve"
    Start-Sleep -Seconds 10
    $dns_resolved = (Resolve-DnsName -Name $NetTarget -Type A -ErrorAction SilentlyContinue)
}
until ($dns_resolved)
Write-HostLog "DNS resolved: $NetTarget = $($dns_resolved.IPAddress)"
