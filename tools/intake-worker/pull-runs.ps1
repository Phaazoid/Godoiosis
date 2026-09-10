<#
  pull-runs.ps1 (#865) - copies a recorded playtest run OUT of the D1 intake and onto this machine,
  in the shape `Session > Replay` already reads, so a run somebody else played can be replayed here.

  THE PIPE IS WRITE-ONLY BY CONSTRUCTION and this script does not change that: the Worker has two
  routes and both are POST, and ReplayRun reads local disk only. A read route on the Worker was the
  obvious design and is the dangerous one - ENDPOINT is a const in the shipped game, so the URL is
  effectively public, which is fine for something that only ACCEPTS uploads and stops being fine the
  moment it hands runs back. It would need auth of its own, and a secret compiled into a dev build is
  not a secret. wrangler is already authenticated as the account owner, so the query IS the mechanism.

  RUNS LAND IN sent/, NEVER pending/. TelemetryUploader._send_round walks TelemetryStore.pending_runs(),
  so a run dropped in pending/ would be shipped straight back up to the intake it just came from.

  NO STATE FILE. What is already on disk IS the state - the same folder-is-the-state rule the rest of
  the arc runs on. read-bug-reports.ps1 needs a last-seen ledger because Discord messages have no
  local footprint; a run does, so this must not grow one.

  See README.md -> Pulling a run back down.
#>

param(
    [switch]$List,                          # show what is in D1, and whether each run is already here
    [string]$RunId = '',                    # pull exactly this one (default: everything not on disk)
    [switch]$Force,                         # overwrite a run that is already on disk
    [string]$Database = 'iosis-telemetry'
)

$ErrorActionPreference = 'Stop'

# A RUN ID IS UNTRUSTED INPUT. It arrives from whatever a client uploaded, and the intake checks only
# that it is a non-empty string - so a crafted one reaches D1 intact and would land here in two
# dangerous places at once: interpolated into a SQL string, and used as a folder name under sent/.
# The no-argument mode walks every id the table returns, so nothing is hand-checked on the way past.
#
# This is the exact shape MissionLog mints - _stamp() (an ISO datetime with : and T replaced) plus an
# underscore plus 8 hex characters off the CSPRNG - and nothing else is accepted.
$RUN_ID_PATTERN = '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_[0-9a-f]{8}$'

function Assert-RunId {
    param([string]$Id)
    if ($Id -notmatch $RUN_ID_PATTERN) {
        throw ("Refusing run id '$Id': not the shape MissionLog mints. A run id is untrusted input " +
               "and this one would be interpolated into SQL and used as a folder name.")
    }
}

# user:// on Windows is %APPDATA%\Godot\app_userdata\<application/config/name>. The project NAME is
# read out of project.godot rather than typed here, so there is one answer to what this game is called.
function Get-TelemetryRoot {
    $projectFile = Join-Path $PSScriptRoot '..\..\project.godot'
    if (-not (Test-Path $projectFile)) {
        throw "Cannot find $projectFile - run this from inside the repo, at tools/intake-worker/."
    }
    $match = Select-String -Path $projectFile -Pattern '^config/name="(.+)"$' | Select-Object -First 1
    if (-not $match) { throw "project.godot has no application/config/name." }
    $name = $match.Matches[0].Groups[1].Value
    return (Join-Path $env:APPDATA "Godot\app_userdata\$name\telemetry")
}

# Which install this machine is, for the listing only. Absent is not an error: a machine that has
# never run the game has no cfg, and the listing is still perfectly readable without the marker.
function Get-LocalInstallId {
    param([string]$Root)
    $cfg = Join-Path $Root 'telemetry.cfg'
    if (-not (Test-Path $cfg)) { return '' }
    $match = Select-String -Path $cfg -Pattern '^install_id="(.+)"$' | Select-Object -First 1
    if (-not $match) { return '' }
    return $match.Matches[0].Groups[1].Value
}

# THE CONSOLE CODEPAGE DECIDES WHETHER NON-ASCII SURVIVES, and it decides BEFORE the JSON is parsed,
# so getting it wrong is unrecoverable rather than merely ugly. wrangler is a native command and
# PowerShell decodes its stdout with [Console]::OutputEncoding: measured on this machine, a UTF-8
# e-acute arrives under cp437 as box-drawing characters (U+251C U+2310) and under cp1252 as 'A-tilde
# c-cedilla' - and would then be written to disk in that corrupted form. Only 65001 round-trips.
# This is the read-side twin of the no-BOM rule below.
#
# STDOUT ONLY - never 2>&1. Redirecting a native command's stderr in PowerShell 5.1 wraps each line in
# an ErrorRecord and sets $? false on exit 0, and here it would also splice wrangler's progress
# banners into the JSON about to be parsed.
function Invoke-D1 {
    param([string]$Sql)
    $saved = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $out = & wrangler d1 execute $Database --remote --json --command $Sql
    } finally {
        [Console]::OutputEncoding = $saved
    }
    if ($LASTEXITCODE -ne 0) { throw "wrangler exited $LASTEXITCODE running: $Sql" }
    return (Get-Rows (($out | Out-String).Trim()))
}

# WHAT SHAPE wrangler --json RETURNS IS NOT ASSUMED HERE. It may print something ahead of the JSON,
# and the rows may sit at the top level or under .results. Both are accepted, and if neither is there
# the failure QUOTES what actually arrived instead of guessing - so one real run is enough to learn
# the shape rather than a round of blind edits.
function Get-Rows {
    param([string]$Text)

    $attempts = @($Text)
    $start = $Text.IndexOfAny([char[]]@('[', '{'))
    if ($start -gt 0) { $attempts += $Text.Substring($start) }

    $parsed = $null
    foreach ($candidate in $attempts) {
        try { $parsed = $candidate | ConvertFrom-Json; break } catch { }
    }
    if ($null -eq $parsed) {
        $head = $Text.Substring(0, [Math]::Min(200, $Text.Length))
        throw "wrangler did not return JSON. First 200 characters of what it did return:`n$head"
    }

    $first = if ($parsed -is [Array]) { if ($parsed.Count -gt 0) { $parsed[0] } else { $null } } else { $parsed }
    if ($null -ne $first -and ($first.PSObject.Properties.Name -contains 'results')) {
        return @($first.results)
    }
    return @($parsed)
}

# A TRUNCATED DOWNLOAD MUST NOT BE ABLE TO LOOK LIKE A CRASH. MissionLog.sweep_unsealed() runs at every
# launch over ReplayRun.list_runs(), which merges BOTH folders, and finishes any run with no
# mission_end by writing a CRASHED ending stamped swept:true. So a half-written blob does not fail
# loudly - it gets "finished" into a completely plausible player crash, which is then evidence you
# would go and investigate. A run can only reach D1 sealed, so a blob whose last line is not the
# summary is ALWAYS a bad pull and never a real record.
function Assert-Sealed {
    param([string]$Events, [string]$Id)
    $lines = @($Events -split "`n" | Where-Object { $_.Trim() -ne '' })
    if ($lines.Count -eq 0) { throw "Run $Id came back with no events at all." }
    $kind = $null
    try { $kind = ($lines[-1] | ConvertFrom-Json).event } catch { }
    if ($kind -ne 'summary') {
        throw ("Run $Id is not sealed - its last line is '$kind', not 'summary'. Refusing to write " +
               "it: the next launch's sweep would finish it as CRASHED and it would read as a real " +
               "player crash. Re-run the pull.")
    }
}

# NO BOM, EVER. In PowerShell 5.1 both `Set-Content -Encoding utf8` and `Out-File -Encoding utf8`
# write EF BB BF (measured, all three ways) and only this one does not. ReplayRun.load_events runs
# JSON.parse_string on line 1, and a BOM is not whitespace so strip_edges() leaves it there: the run
# would report "line 1 is not valid JSON -- run truncated there" and come back empty. WriteAllText
# also passes the text through byte-exact, so the blob's own newlines survive untranslated.
function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

# ATOMIC, by building in a temp folder and renaming. A failure between the two files would otherwise
# leave a half-written run that the already-on-disk check then skips forever, which is the worst of
# both outcomes. TelemetryStore.rewrite_run_events uses this same idiom for the same reason.
function Save-Run {
    param([string]$Id, [string]$Events, $Board, [string]$SentDir)

    $final = Join-Path $SentDir $Id
    $tmp = Join-Path $SentDir ".pull-$Id"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force $tmp | Out-Null

    Write-Utf8NoBom (Join-Path $tmp 'events.jsonl') $Events

    # board is NULLABLE: the client skips a board.tres that failed to write, so a run without one is
    # legal. It lists and its metrics read fine; ReplayRun.can_replay() is false, because the seed is
    # what a replay needs.
    $hasBoard = ($Board -is [string]) -and ($Board.Length -gt 0)
    if ($hasBoard) { Write-Utf8NoBom (Join-Path $tmp 'board.tres') $Board }

    if (Test-Path $final) { Remove-Item $final -Recurse -Force }
    Move-Item $tmp $final
    return $hasBoard
}

# ---------------------------------------------------------------------------------------------

$root = Get-TelemetryRoot
$sentDir = Join-Path $root 'sent'
$pendingDir = Join-Path $root 'pending'
New-Item -ItemType Directory -Force $sentDir | Out-Null

$onDisk = @()
foreach ($dir in @($sentDir, $pendingDir)) {
    if (Test-Path $dir) { $onDisk += @(Get-ChildItem $dir -Directory | ForEach-Object { $_.Name }) }
}

Write-Host "Telemetry folder: $root"
Write-Host "Already on disk:  $($onDisk.Count) run(s)"

$rows = @(Invoke-D1 ('select run_id, install_id, scenario, outcome, rounds, trivial, received_at ' +
                   'from runs order by received_at desc'))
Write-Host "In the intake:    $($rows.Count) run(s)"
Write-Host ''

$localInstall = Get-LocalInstallId $root

if ($List) {
    foreach ($row in $rows) {
        $here = if ($onDisk -contains $row.run_id) { 'here ' } else { '     ' }
        $whose = if ($row.install_id -eq $localInstall) { 'this machine' } else { $row.install_id }
        $scenario = if ($row.scenario) { Split-Path $row.scenario -Leaf } else { '(sandbox)' }
        $flag = if ($row.trivial -eq 1) { ' trivial' } else { '' }
        Write-Host ("{0} {1}  {2,-14} {3,-22} {4,-10} r{5}{6}" -f `
            $here, $row.run_id, $whose, $scenario, $row.outcome, $row.rounds, $flag)
    }
    return
}

if ($RunId -ne '') {
    Assert-RunId $RunId
    $targets = @($rows | Where-Object { $_.run_id -eq $RunId })
    if ($targets.Count -eq 0) { throw "No run '$RunId' in the intake. Try -List." }
} else {
    $targets = @($rows | Where-Object { $Force -or ($onDisk -notcontains $_.run_id) })
}

if ($targets.Count -eq 0) {
    Write-Host 'Nothing to pull - every run in the intake is already on this machine.'
    return
}

$pulled = 0
$boardless = 0
foreach ($row in $targets) {
    $id = $row.run_id
    Assert-RunId $id

    if (($onDisk -contains $id) -and -not $Force) {
        Write-Host "  skip  $id (already here; -Force to overwrite)"
        continue
    }

    $blob = @(Invoke-D1 "select events, board from runs where run_id = '$id'")
    if ($blob.Count -eq 0) { throw "Run $id vanished between the two queries." }

    $events = [string]$blob[0].events
    Assert-Sealed $events $id
    $hasBoard = Save-Run $id $events $blob[0].board $sentDir

    $note = if ($hasBoard) { '' } else { '  (no board - lists, but cannot be replayed)' }
    Write-Host ("  pull  $id  $([Math]::Round($events.Length / 1KB)) KB$note")
    $pulled++
    if (-not $hasBoard) { $boardless++ }
}

Write-Host ''
Write-Host "Pulled $pulled run(s) into $sentDir"
if ($boardless -gt 0) { Write-Host "$boardless had no board snapshot and cannot be replayed." }
Write-Host 'They are in Session > Replay now - no relaunch needed if the tab is re-opened.'
