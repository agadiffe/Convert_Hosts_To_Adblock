#=================================================================================================================
#                                      Convert Hosts file to Adblock syntax
#=================================================================================================================

# 'Powershell Core' is 5x faster than 'Windows Powershell' (at least, for regex things).
#Requires -Version 7.4

<#
.SYNTAX
    .\Convert-HostsToAdblock.ps1 -FilePath <string> [-NoComment] [<CommonParameters>]

    .\Convert-HostsToAdblock.ps1 -Uri <string> [-NoComment] [<CommonParameters>]

    .\Convert-HostsToAdblock.ps1 -StringData <string> [-NoComment] [<CommonParameters>]

.NOTES
    each rules must contains only a single URL/IP (except for 'localhost' related rules)
    e.g. '0.0.0.0 example.org' or '0.0.0.0 1.2.3.4'
#>

[CmdletBinding(DefaultParameterSetName = 'File')]
param
(
    [Parameter(
        ParameterSetName = 'File',
        Mandatory)]
    [string]
    $FilePath,

    [Parameter(
        ParameterSetName = 'Url',
        Mandatory)]
    [string]
    $Uri,

    [Parameter(
        ParameterSetName = 'String',
        Mandatory)]
    [string]
    $StringData,

    [switch]
    $NoComment
)

try
{
    $HostsContent = switch ($PSCmdlet.ParameterSetName)
    {
        'File'   { [IO.File]::ReadAllLines($FilePath) }
        'Url'    { (Invoke-RestMethod -Uri $Uri) -split '(?:\r)?\n' }
        'String' { $StringData -split '(?:\r)?\n' }
    }
}
catch
{
    throw
}

<#
list of localhost domain to comment. e.g.

127.0.0.1 localhost # comment
::1       ip6-localhost ip6-loopback
#>
$LocalhostNames = @(
    'localhost'
    'localhost.localdomain'
    'local'
    'broadcasthost'
    'ip6-localhost'
    'ip6-loopback'
    'ip6-localnet'
    'ip6-mcastprefix'
    'ip6-allnodes'
    'ip6-allrouters'
    'ip6-allhosts'
    '0.0.0.0'
)

# convert hosts comment to adblock comment
$HostsContent = $HostsContent -replace '^\s*#', '! $&'

# comment 'localhost' related rules
$RegexLocalhostNames = ($LocalhostNames -join '|').Replace('.', '\.')
$RegexLocalhost = "^(?!!)\s*\S+\s+(?:(?:$RegexLocalhostNames)\s*)+\s*(?:#.*)?$"
$HostsContent = $HostsContent -replace $RegexLocalhost, '! $&'

# remove loopback/void/any IP from the beginning of each rules
$HostsContent = $HostsContent -replace '^(?!!)\s*\S+\s+'

# remove comment that's on the same line as rules
# (actually remove everything after the first domain)
$HostsContent = $HostsContent -replace '^(?!!)(\S+).*', '$1'

# remove 'www.' from URLs (e.g. convert 'www.foo.tld' to 'foo.tld')
$HostsContent = $HostsContent -replace '^www\.'

# remove duplicate (mainly (but not only) due from the deletion of 'www.')
# [ordered] is important to have a faster process time in 'remove redundant rules'
$UniqueRules = [ordered]@{}
$HostsContent = foreach ($Item in $HostsContent)
{
    if ($Item -match '^(?:!|\s*$)')
    {
        $Item
    }
    else
    {
        if (-not $UniqueRules.Contains($Item))
        {
            $UniqueRules[$Item] = $null
            $Item
        }
    }
}

# do not keep comment and empty line if the option is enabled
if ($NoComment)
{
    $HostsContent = $UniqueRules.Keys
}

# comment IP address rules
$HostsContent = $HostsContent -replace '^(?!!).+(?:\.\d+|:.*)$', '!%! $&'

# remove redundant rules
#
# if bar.tld exist, remove whatever.bar.tld
# if foo.bar.tld exist, remove whatever.foo.bar.tld
# if world.foo.bar.tld exist, remove whatever.world.foo.bar.tld
# ...
#
# 'whatever' can include several subdomains. e.g.
# whatever.bar.tld -> x.y.z.bar.tld
# whatever.world.foo.bar.tld -> a.b.c.world.foo.bar.tld
#
# the following numbers are informative to have an order of magnitude
# tested with StevenBlack hosts file 3.14.71 with only the script running
# (the process time might vary according to your hardware)
#
# StevenBlack Unified hosts (adware + malware):
# $HostsContent:            135,053 lines / 128,271 rules
# $Hosts no Duplicate:       88,296 lines /  81,514 rules
# after $RegexSubTLD.One:    74,889 lines /  68,106 rules / 10s
# after $RegexSubTLD.Two:    73,992 lines /  67,209 rules / 21s
# after $RegexSubTLD.Three:  73,857 lines /  67,074 rules / 22s
# after $RegexSubTLD.Four:   73,842 lines /  67,059 rules / 23s
# after $RegexSubTLD.Five:   73,838 lines /  67,055 rules / 23s
# after $RegexSubTLD.Six:    73,830 lines /  67,047 rules / 23s
#
# StevenBlack Unified hosts + fakenews + gambling + porn + social:
# $HostsContent:            231,883 lines / 224,943 rules
# $Hosts no Duplicate:      166,727 lines / 159,842 rules
# after $RegexSubTLD.One:   134,212 lines / 127,327 rules / 46s
# after $RegexSubTLD.Two:   133,273 lines / 126,388 rules / 1min 06s
# after $RegexSubTLD.Three: 133,133 lines / 126,248 rules / 1min 07s
# after $RegexSubTLD.Four:  133,118 lines / 126,233 rules / 1min 08s
# after $RegexSubTLD.Five:  133,114 lines / 126,229 rules / 1min 08s
# after $RegexSubTLD.Six:   133,106 lines / 126,221 rules / 1min 08s
#
$RemainingUrlsCountToProcess = -1
for ($i = 1; $RemainingUrlsCountToProcess; $i++)
{
    $UrlsWithFixNumOfSubDomain = $HostsContent -match "^(?!!)(?:[^.]+\.){$i}[^.]+$"
    $RegexSubTLD = ($UrlsWithFixNumOfSubDomain -join '|').Replace('.', '\.')
    $RegexSubTLD = "^(?!!).+\.(?:$($RegexSubTLD))$"
    $HostsContent = $HostsContent -notmatch $RegexSubTLD
    $RemainingUrlsCountToProcess = ($HostsContent -match "^(?!!)(?:[^.]+\.){$($i + 1),}[^.]+$").Count
}

# uncomment IP address rules
$HostsContent = $HostsContent -replace '^!%! '

# convert rules to adblock syntax
$HostsContent = $HostsContent -replace '^(?!!)\S+', '||$&^'

# add the number of rules at the top of the file
$RulesCount = ($HostsContent -match '^\|').Count
$InfoToAdd = @(
    "! # Hosts file converted to Adblock syntax : $($RulesCount.ToString('N0')) rules"
    "! # =========================================================="
)
if ($NoComment)
{
    $HostsTitle = $HostsContent -match 'Title:'
    $HostsDate = $HostsContent -match 'Date:|modified:|updated:'
    $InfoToAdd = @( $HostsTitle[0]; $HostsDate[0]) + $InfoToAdd
}
$HostsContent = $InfoToAdd + $HostsContent

# return the converted hosts file
$HostsContent
