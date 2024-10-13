#=================================================================================================================
#                                Convert StevenBlack Hosts file to Adblock syntax
#=================================================================================================================

# If you can't use Powershell Core, add '-Encoding utf8' to 'Out-File'
#Requires -Version 7.4

<#
.SYNTAX
    .\Convert-StevenBlackHostsToAdblock.ps1 [[-FileName] <string>] [-Online] [-NoComment] [<CommonParameters>]
#>

[CmdletBinding()]
param
(
    [string]
    $FileName = 'hosts',

    [switch]
    $Online,

    [switch]
    $NoComment
)

$HostsData = @{
    Local  = @{
        Source      = "$PSScriptRoot\$FileName"
        Destination = "$PSScriptRoot\$FileName.adblock_syntax"
        GetContent  = 'Get-Content -Raw -Path $HostsData.Local.Source'
    }
    Online = @{
        Source      = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts'
        Destination = "$PSScriptRoot\$FileName.adblock_syntax"
        GetContent  = 'Invoke-RestMethod -Uri $HostsData.Online.Source'
    }
}

$HostsLocation = $Online ? 'Online' : 'Local'
$OutputFile = $HostsData.$HostsLocation.Destination

try
{
    $HostsSourceContent = Invoke-Expression -Command $HostsData.$HostsLocation.GetContent
}
catch
{
    throw
}

function Get-StevenBlackHostsFileDate
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $StringData
    )

    if ($StringData -match '# Date: \d{2} [A-Za-z]+ \d{4} \d{2}:\d{2}:\d{2} \(UTC\)')
    {
        $RawDate = $Matches[0] -replace '^# Date: (.+) \(UTC\)$', '$1'
        [Datetime]::ParseExact($RawDate, 'dd MMM yyyy HH:mm:ss', $null)
    }
}

if (Test-Path -Path $OutputFile)
{
    $OutputFileContent = Get-Content -Raw -Path $OutputFile
    $OutputFileDate = Get-StevenBlackHostsFileDate -StringData $OutputFileContent
}

$HostsSourceDate = Get-StevenBlackHostsFileDate -StringData $HostsSourceContent

if ($null -eq $HostsSourceDate -or $OutputFileDate -lt $HostsSourceDate)
{
    $ScriptParam = @{
        StringData = $HostsSourceContent
        NoComment  = $NoComment
    }
    $HostsContentConverted = & "$PSScriptRoot\Convert-HostsToAdblock.ps1" @ScriptParam

    Out-File -InputObject $HostsContentConverted -FilePath $OutputFile
    Write-Host "Hosts file converted to: '$OutputFile'"
}
else
{
    Write-Host "Converted Hosts file ('$OutputFile') is already up to date"
}
