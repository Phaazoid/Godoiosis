<#
  read-bug-reports.ps1 (#131 follow-up) - pulls bug/feedback reports posted to the Discord channel
  that tools/report-worker relays into, and prints each one's note text plus its full report.md body.

  Credentials live OUTSIDE this repo (Godoiosis is public) in a file this script never creates for
  you - see README.md in this folder for one-time bot setup. Remembers the newest message ID it has
  shown so a plain re-run only surfaces reports that arrived since last time.
#>

param(
    [switch]$All,       # ignore saved state, show the $Limit most recent reports regardless
    [int]$Limit = 25,   # how many recent messages to ask Discord for (max 100)
    [switch]$NoFetch    # skip downloading each report.md body; just show the note + attachment links
)

$ErrorActionPreference = 'Stop'

$SecretsPath = Join-Path $env:USERPROFILE '.iosis-secrets\discord-bot.env'
$StatePath   = Join-Path $env:USERPROFILE '.iosis-secrets\discord-bot-state.json'

if (-not (Test-Path $SecretsPath)) {
    Write-Error "Missing $SecretsPath - see README.md for setup."
}

$envVars = @{}
Get-Content $SecretsPath | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)=(.*)$') {
        $envVars[$Matches[1]] = $Matches[2]
    }
}
$Token = $envVars['DISCORD_BOT_TOKEN']
$ChannelId = $envVars['DISCORD_CHANNEL_ID']
if (-not $Token -or -not $ChannelId) {
    Write-Error "DISCORD_BOT_TOKEN or DISCORD_CHANNEL_ID missing from $SecretsPath"
}

$lastSeenId = [uint64]0
if ((Test-Path $StatePath) -and -not $All) {
    $state = Get-Content $StatePath -Raw | ConvertFrom-Json
    if ($state.last_message_id) { $lastSeenId = [uint64]$state.last_message_id }
}

$headers = @{
    Authorization = "Bot $Token"
    # Discord's edge returns a generic "internal network error" (code 40333) to requests using
    # PowerShell's default .NET User-Agent - an explicit one (Discord's own recommended format)
    # avoids it. curl is unaffected; this bit only PowerShell's Invoke-RestMethod.
    'User-Agent' = 'IosisBugReportReader (https://github.com/Phaazoid/Godoiosis, 1.0)'
}
$uri = "https://discord.com/api/v10/channels/$ChannelId/messages?limit=$Limit"
# Invoke-RestMethod's automatic JSON parsing has been observed merging a JSON array of objects
# into one object (each property becoming an array of every element's value) instead of returning
# one object per array element - Invoke-WebRequest + an explicit ConvertFrom-Json does not do this.
# The @(...) array-safety wrap (needed since ConvertFrom-Json collapses a single-element JSON array
# to a bare object) must NOT wrap the "| ConvertFrom-Json" pipeline itself - @(X | ConvertFrom-Json)
# reproduced the same merge bug; parse into a plain variable first, then wrap that.
$resp = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -UseBasicParsing
$parsedMessages = $resp.Content | ConvertFrom-Json
$messages = @($parsedMessages)

# Built by hand rather than Sort-Object/Where-Object/Measure-Object piping: this environment's
# PowerShell has been observed silently mishandling large [uint64] snowflake IDs at every one of
# those steps (a single-match filter collapses to a bare object instead of a 1-element array; a
# maximum taken via Measure-Object comes back coerced through [double], losing precision on an ID
# this large and corrupting the saved state - both measured while building this script). A plain
# loop with explicit [uint64] comparisons avoids all three failure modes at once.
$ordered = New-Object System.Collections.ArrayList
foreach ($m in $messages) { [void]$ordered.Add($m) }
$ordered = $ordered | Sort-Object { [uint64]$_.id }
$maxIdSeen = $lastSeenId

$toShow = New-Object System.Collections.ArrayList
foreach ($msg in $ordered) {
    $id = [uint64]$msg.id
    if ($id -gt $maxIdSeen) { $maxIdSeen = $id }
    if ($All -or $id -gt $lastSeenId) { [void]$toShow.Add($msg) }
}

if ($toShow.Count -eq 0) {
    Write-Output "No new reports since last check."
} else {
    foreach ($msg in $toShow) {
        Write-Output "========================================"
        Write-Output $msg.content
        Write-Output "Posted: $($msg.timestamp)"

        $reportMd = $msg.attachments | Where-Object { $_.filename -eq 'report.md' } | Select-Object -First 1
        if ($reportMd -and -not $NoFetch) {
            Write-Output "--- report.md ---"
            try {
                $mdResp = Invoke-WebRequest -Uri $reportMd.url -Headers @{ 'User-Agent' = $headers.'User-Agent' } -Method Get -UseBasicParsing
                $body = $mdResp.Content
                Write-Output $body
            } catch {
                Write-Output "(failed to fetch report.md: $_)"
            }
        }
        foreach ($att in $msg.attachments) {
            Write-Output "  [$($att.filename)] $($att.url)"
        }
    }
    Write-Output "========================================"
    Write-Output "$($toShow.Count) report(s) shown."
}

if (-not $All -and $maxIdSeen -gt $lastSeenId) {
    # last_message_id is written with an explicit ToString() - string-interpolating a [uint64] this
    # large has separately been observed round-tripping through [double] and losing precision.
    $stateJson = '{"last_message_id":"' + $maxIdSeen.ToString() + '"}'
    Set-Content -Path $StatePath -Value $stateJson -Encoding utf8
}
