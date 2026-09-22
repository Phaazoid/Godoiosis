<#
  archive-build.ps1 (#1027) - makes a build that can be handed out: exports it from a clean tree,
  zips it beside the export, and TAGS the commit it was built from.

  THE TAG IS THE POINT, not the zip. A report from somebody else's machine carries a version string
  and nothing else - Checkout.describe() answers "" in a player build by construction, so `v0.188.3`
  is the whole of what comes back. Nothing in the repo maps one of those to a commit: there are 398
  "Version x.y.z" commits, version-bump.yml does not tag, and a build is anyway exported from the
  WORKING TREE, so one taken mid-authoring matches no commit at all. The tag says both things at
  once - this version existed as a real build, and here is the checkout it came from.

  WHY IT EXPORTS RATHER THAN ARCHIVING builds/ (dev, 2026-09-18): the clean-tree check then guards
  the ARTIFACT instead of only its label. A script that zips whatever is already sitting in builds/
  can refuse a stale export but cannot prevent one.

  THE ORDER IS LOAD-BEARING. Nothing durable is written until the export has succeeded, and the tag
  goes LAST - so a failed run leaves behind no zip claiming to be a build, and no tag pointing at
  one that was never made.

  DEBUG, NOT RELEASE. What has been handed out so far is a debug export - the .console.exe beside
  Iosis.exe is written by `debug/export_console_wrapper=1`, which is Debug Only - so --export-debug
  reproduces it. Switching to --export-release changes what a tester runs (is_debug_build, and how
  eagerly the engine flushes the log a bug report tails) and is a call to make deliberately.

  ONE FILE, BECAUSE THE PACK IS EMBEDDED (#1029, dev 2026-09-18). `binary_format/embed_pck=true`
  appends the game to the executable, so a player can be handed the exe alone. Before that it was
  a 98 MB runtime whose game sat in a 13.6 MB .pck beside it, and a bare exe uploaded to itch could
  not find it - and a ZIP has the same failure, because Windows runs an exe straight out of its own
  archive preview without extracting the pack next to it.

  So whether a .pck exists is the PRESET's answer, never this script's. The check is narrowed rather
  than dropped: with embed_pck off, a missing pack is exactly the fault above, and refusing on it is
  the whole point of looking.

  NOTHING HERE IS TYPED TWICE. The engine comes from $env:GODOT_BIN exactly as tests\run_tests.ps1
  reads it, the version from project.godot (Build.version()'s one store), and the export path and
  the build's own name from export_presets.cfg - so an editor export and a scripted one land in the
  same place by construction rather than by agreement.

  IT ALSO PUTS THE BUILD OUT (#1060). butler uploads the zip to itch, and the last thing the script
  does is ANNOUNCE the new version into the intake Worker's `release` row, which is what the game's
  own update nag reads on every launch.

  THE ORDER GREW A STEP AND ITS MEANING HELD. Once "a build that goes out" means one that is ON
  itch, the tag's claim is only true after the upload - so the push goes BEFORE the tag, and the
  announce goes after everything. Each prefix fails safe: a failed push leaves no tag and nobody
  nagged; a failed tag or announce leaves a build up that nobody has been pointed at yet. All three
  recover by re-running at the same commit, which section 4 already allows.

  AND IT REFUSES A VERSION WITH NO NOTES (#1075). Every build that goes out has an entry in
  CHANGELOG.md, which the game ships and reads for its what's-new card, so the check sits with the
  others before anything durable is written. The entry arrives by a release PR merged last; the
  procedure is at the top of CHANGELOG.md.

  Usage:
    powershell -File tools\archive-build.ps1             # export, zip, upload, tag, announce
    powershell -File tools\archive-build.ps1 -NoPush     # everything but pushing the git tag
    powershell -File tools\archive-build.ps1 -NoUpload   # everything but itch and the announce
#>

param(
    [switch]$NoPush,
    [switch]$NoUpload
)

$ErrorActionPreference = 'Stop'

# How long the archive waits out something holding a build file. ~10s, comfortably past a virus
# scan of a 112 MB binary, and short enough that a real lock refuses rather than hangs.
$ZIP_ATTEMPTS = 5
$ZIP_RETRY_SECONDS = 2

# WHERE A BUILD GOES (#1060). user/game:channel -- the CHANNEL NAME carries the platform, so
# "windows" in it is what tags the upload as a Windows executable on the itch page.
$ITCH_TARGET = 'phlogistongames/iosis:windows'

# Where the in-game nag sends somebody on an old build. THE AUTHORITY IS THE `release` ROW, not
# this line: the game reads the row, and this is what overwrites it each release. The seed value in
# alter-2026-09-20-release.sql exists only so the route can answer before the first push.
$DOWNLOAD_URL = 'https://phlogistongames.itch.io/iosis'

# The intake Worker's database. Its config path is built from $root below, not from here.
$TELEMETRY_DB = 'iosis-telemetry'

$root = Split-Path $PSScriptRoot -Parent

# --config is needed because wrangler looks for a wrangler.toml in the CURRENT DIRECTORY, and this
# script does not run in the Worker's folder -- pull-runs.ps1 gets away without it only because it
# sits there. ABSOLUTE, off $root, for the reason every other path in this file is: nothing here may
# depend on where it was invoked from, and a relative path would work from the repo root and fail
# silently-looking ("no config file found") from anywhere else.
$WORKER_CONFIG = Join-Path $root 'tools\intake-worker\wrangler.toml'

# One reader for "what does this config file say", used for the version and for both halves of the
# export path. Refuses rather than returning empty: every one of these is load-bearing downstream,
# and a blank version would mint a tag called "v".
function Read-Setting {
    param([string]$Path, [string]$Pattern, [string]$What)
    if (-not (Test-Path $Path)) { throw "Cannot find $Path - run this from inside the repo." }
    $match = Select-String -Path $Path -Pattern $Pattern | Select-Object -First 1
    if (-not $match) { throw "$Path has no $What." }
    return $match.Matches[0].Groups[1].Value
}

# Its tolerant twin, for a setting whose ABSENCE has a defined meaning. Only embed_pck uses it, and
# the default has to be the one whose guess fails LOUDLY: reading a separate pack that is not there
# is a refusal, where skipping a pack that should be there ships the build that cannot find its own
# game. Godot's own default is false, so the safe answer is also the correct one.
function Read-Setting-Or {
    param([string]$Path, [string]$Pattern, [string]$Fallback)
    $match = Select-String -Path $Path -Pattern $Pattern | Select-Object -First 1
    if (-not $match) { return $Fallback }
    return $match.Matches[0].Groups[1].Value
}

# THE ARCHIVE, AND WHY IT IS NOT `Compress-Archive` (#1031). That cmdlet opens each source with a
# RESTRICTIVE share mode, so anything else touching the file fails the whole archive - which is what
# happened on the first embedded build: Windows Defender scanning a freshly written 112 MB binary.
# It also refuses the obvious workflow of launching the build to test it and then re-exporting,
# because a running executable is readable on Windows but not to that cmdlet.
#
# So the read asks for `FileShare.ReadWrite` - a holder that permits reading no longer fails us -
# and the RETRY covers the other shape, a brief EXCLUSIVE lock that no share mode can open. Both
# halves are here because the two causes are different: one is a reader, one is a scanner.
#
# Entries are written BY NAME, which makes the flat layout structural rather than a side effect of
# handing a cmdlet a file list. A partial zip is deleted on every failure, so a truncated archive
# can never sit in the output directory looking like a build.
function New-Zip {
    param([string[]]$Files, [string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    for ($attempt = 1; $attempt -le $ZIP_ATTEMPTS; $attempt++) {
        if (Test-Path $Destination) { Remove-Item $Destination -Force }
        try {
            $archive = [IO.Compression.ZipFile]::Open($Destination, 'Create')
            try {
                foreach ($file in $Files) {
                    $entry = $archive.CreateEntry([IO.Path]::GetFileName($file), 'Optimal')
                    $writer = $entry.Open()
                    try {
                        $reader = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
                        try { $reader.CopyTo($writer) } finally { $reader.Dispose() }
                    } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
            return
        } catch {
            $why = $_.Exception.Message
            if ($attempt -lt $ZIP_ATTEMPTS) {
                Write-Host ("Something is holding a build file; retrying ({0}/{1})..." -f $attempt, $ZIP_ATTEMPTS) -ForegroundColor Yellow
                Start-Sleep -Seconds $ZIP_RETRY_SECONDS
            } else {
                if (Test-Path $Destination) { Remove-Item $Destination -Force }
                throw ("Could not read a build file after $ZIP_ATTEMPTS attempts - no zip written," +
                       " no tag created. Something is holding it: a virus scan that has not finished," +
                       " or the game still running out of that folder. Close it and run this again.`n" +
                       "  $why")
            }
        }
    }
}

# Takes ONE array rather than remaining arguments: a token like `--porcelain` handed to an advanced
# function is parsed as a parameter NAME, not as data, so the flags have to arrive already packed.
function Invoke-Git {
    param([string[]]$Argv)
    $out = & git -C $root @Argv
    if ($LASTEXITCODE -ne 0) { throw "git $($Argv -join ' ') exited $LASTEXITCODE" }
    return $out
}

# ---- 1. the engine -----------------------------------------------------------------------------
# Same variable and same default as tests\run_tests.ps1, deliberately: one answer to "which Godot
# does this project drive headlessly", whichever script is asking.

$bin = $env:GODOT_BIN
if (-not $bin) { $bin = "C:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe" }
if (-not (Test-Path $bin)) {
    throw "Godot not found at '$bin'. Set `$env:GODOT_BIN to your Godot 4.7 console exe."
}

# ---- 2. a clean tree ---------------------------------------------------------------------------
# THE WHOLE GUARD. An export reads the working tree, not HEAD, so this is what makes the tag's claim
# true - without it the tag names a commit that may share nothing with the binary beside it.
# Untracked files count: a stray .gd or .tres is content the pack would happily swallow.

$dirt = Invoke-Git @('status', '--porcelain')
if ($dirt) {
    throw ("Refusing to build from a dirty tree - an export reads the tree, so the tag would name a" +
           " commit the binary does not match. Commit, stash or clean these first:`n" +
           (($dirt | ForEach-Object { "  $_" }) -join "`n"))
}

# ---- 3. what this build is ---------------------------------------------------------------------

$presets = Join-Path $root 'export_presets.cfg'
$version = Read-Setting (Join-Path $root 'project.godot') '^config/version="(.+)"$' 'application/config/version'
$exportPath = Read-Setting $presets '^export_path="(.+)"$' 'an export_path'
$embedded = (Read-Setting-Or $presets '^binary_format/embed_pck=(.+)$' 'false') -eq 'true'

# export_path is relative to the project root, and the preset writes the other two files beside the
# exe under its own base name - so the exe's name is where "what is this build called" is answered.
$exe = [IO.Path]::GetFullPath((Join-Path $root $exportPath))
$outDir = Split-Path $exe -Parent
$name = [IO.Path]::GetFileNameWithoutExtension($exe)
$pck = Join-Path $outDir "$name.pck"
$console = Join-Path $outDir "$name.console.exe"

$tag = "v$version"
$zip = Join-Path $outDir "$name-$tag.zip"
$sha = "$(Invoke-Git @('rev-parse', '--short=7', 'HEAD'))".Trim()
# Interpolated rather than .Trim()'d directly: a detached HEAD prints nothing at all, and git exits
# 0 having done so, so the call hands back null.
$branch = "$(Invoke-Git @('branch', '--show-current'))".Trim()
if (-not $branch) { $branch = 'detached' }

# ---- 4. has this version already gone out? -----------------------------------------------------
# The duplicate-version trap, made impossible to walk into. A stale project.godot has already minted
# a version two earlier builds wore (2026-08-27) - which is invisible in the game, in a bug report
# and in the log, because every one of them only ever prints the string.

& git -C $root rev-parse -q --verify "refs/tags/$tag^{commit}" > $null
$tagExists = ($LASTEXITCODE -eq 0)
$tagAtHead = $false
if ($tagExists) {
    $tagged = "$(Invoke-Git @('rev-list', '-n', '1', $tag))".Trim()
    $head = "$(Invoke-Git @('rev-parse', 'HEAD'))".Trim()
    $tagAtHead = ($tagged -eq $head)
    if (-not $tagAtHead) {
        throw ("Refusing: $tag already names $($tagged.Substring(0,7)), so this version has been" +
               " built and handed out before. Merge something so version-bump.yml moves the version" +
               " on, then run this again.")
    }
    # Same commit, so this is a re-export of a build that already exists. Legitimate - the zip is
    # overwritten and the tag is left exactly where it is.
    Write-Host "$tag already tags this commit - re-exporting and overwriting the zip." -ForegroundColor Yellow
}

# ---- 4b. the release notes ---------------------------------------------------------------------
# A BUILD THAT GOES OUT HAS AN ENTRY (#1075). CHANGELOG.md is the one record of what each build
# changed, and the game's what's-new card reads it out of the pack -- so a build with no entry tells
# its players nothing and leaves the ledger a hole exactly where a build went out.
#
# Before the export, so a refusal writes nothing. It reads the TREE, which section 2 has just proved
# clean, so the file checked here is the file the pack will carry.
#
# THE HEADING FORMAT HAS A SECOND READER, declared: ReleaseNotes.parse. test_release_notes lints
# every `## ` heading in the file, so a heading this accepts is one the card can parse. -CaseSensitive
# because Select-String is not by default, and the card would not read `## V0.1.0`.

$notes = Join-Path $root 'CHANGELOG.md'
if (-not (Test-Path $notes)) {
    throw "Cannot find $notes - it is the release ledger, and every build needs an entry in it."
}
$notesHeading = '^## v' + [regex]::Escape($version) + '(\s|$)'
if (-not (Select-String -Path $notes -Pattern $notesHeading -CaseSensitive -Quiet)) {
    $newest = Select-String -Path $notes -Pattern '^## v(\S+)' -CaseSensitive | Select-Object -First 1
    $newestText = 'none'
    if ($newest) { $newestText = "v$($newest.Matches[0].Groups[1].Value)" }
    throw ("CHANGELOG.md has no entry for $tag (its newest is $newestText). Add a '## $tag' heading" +
           " with this build's notes. If a release PR named the version main was at before a later" +
           " merge moved it on, retitle that heading directly on main - another PR would bump the" +
           " version again - and run this again.")
}

# ---- 5. the export -----------------------------------------------------------------------------
# Two Godots on one project directory is already this project's normal - the export smoke spawns
# exactly this from inside a running engine, and run_tests.ps1 drives one while the editor is open.

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# A STALE PACK IS A HAZARD, NOT LITTER. Godot resolves an external <name>.pck sitting beside the
# exe, so one left by an earlier un-embedded export would be loaded IN PREFERENCE to the game inside
# the binary - a self-contained build silently running older content - and it would ride into the
# zip besides. The only file this script ever removes, and one it wrote itself.
if ($embedded -and (Test-Path $pck)) {
    Remove-Item $pck -Force
    Write-Host "Removed a stale $([IO.Path]::GetFileName($pck)) - the pack is embedded now." -ForegroundColor Yellow
}

Write-Host "Exporting $name $tag ($branch @ $sha)..." -ForegroundColor Cyan

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $bin --headless --path $root --export-debug "Windows Desktop" $exe
$exportCode = $LASTEXITCODE
$sw.Stop()

if ($exportCode -ne 0) { throw "Godot exited $exportCode - no zip written, no tag created." }

# Godot has been known to exit 0 having written nothing useful, so the artifact is checked rather
# than inferred from the exit code. The pack is required only when the preset keeps it separate.
$required_files = @($exe)
if (-not $embedded) { $required_files += $pck }
foreach ($required in $required_files) {
    if (-not (Test-Path $required)) {
        throw "Godot exited 0 but $required is not there - no zip written, no tag created."
    }
}

# The completion half of the dirty-tree rule, asked where it would actually show: if exporting
# writes anything back into the repo, this is the run that has to say so.
$after = Invoke-Git @('status', '--porcelain')
if ($after) {
    throw ("The export dirtied the tree, so the tag would no longer describe the binary:`n" +
           (($after | ForEach-Object { "  $_" }) -join "`n"))
}

# ---- 6. the zip --------------------------------------------------------------------------------

$files = @($exe)
if (-not $embedded) { $files += $pck }
if (Test-Path $console) { $files += $console }
New-Zip $files $zip

# ---- 7. the upload -----------------------------------------------------------------------------
# THE ZIP, not the directory. butler takes a .zip directly and unpacks it on the far side, so what
# goes up is the artifact this script already made and checked -- where pushing builds\ would sweep
# up every previous version's zip sitting beside it.
#
# --userversion is the version read in section 3, so the itch page and the game cannot disagree
# about what this build is called. It is also what makes itch's own latest-version endpoint work,
# which we do not use but which costs nothing to keep true.

if (-not $NoUpload) {
    if (-not (Get-Command butler -ErrorAction SilentlyContinue)) {
        throw ("butler is not on PATH, so this build cannot go out. Download it from" +
               " https://itchio.itch.io/butler, extract to e.g. C:\butler, add that to PATH," +
               " and run 'butler login' once. Then run this again, or use -NoUpload to build" +
               " without publishing.")
    }
    Write-Host "Uploading $tag to $ITCH_TARGET..." -ForegroundColor Cyan
    # No 2>&1 -- see the announce below for why.
    & butler push $zip $ITCH_TARGET --userversion $version
    if ($LASTEXITCODE -ne 0) {
        throw "butler exited $LASTEXITCODE - no tag created, nothing announced."
    }
}

# ---- 8. the tag --------------------------------------------------------------------------------

if (-not $tagAtHead) {
    Invoke-Git @('tag', '-a', $tag, '-m', "Build $tag -- $branch @ $sha") | Out-Null
    if ($NoPush) {
        Write-Host "Tagged $tag locally. Push it with: git push origin $tag" -ForegroundColor Yellow
    } else {
        Invoke-Git @('push', 'origin', $tag) | Out-Null
    }
}

# ---- 9. the announce, last ---------------------------------------------------------------------
# WHAT THE IN-GAME NAG READS (#1060). Last of everything, so the game can never point somebody at a
# build that is not up yet -- the failure this ordering makes impossible.
#
# wrangler IS THE AUTH. pull-runs.ps1 ruled this for the read side and it holds for a write: "a
# secret compiled into a dev build is not a secret. wrangler is already authenticated as the account
# owner, so the query IS the mechanism." So the Worker has no write route, this needs no token, and
# there is nothing here that could leak into a build.
#
# NO 2>&1 on wrangler: redirecting a native command's stderr in PowerShell 5.1 wraps each line in an
# ErrorRecord and sets $? false on exit 0.

if (-not $NoUpload) {
    $announcedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $sql = ("UPDATE release SET version = '$version', url = '$DOWNLOAD_URL'," +
            " announced_at = '$announcedAt' WHERE id = 1;")
    Write-Host "Announcing $tag to the update check..." -ForegroundColor Cyan
    # RUN IT FROM THE WORKER'S FOLDER. wrangler writes .wrangler/cache into the CURRENT directory
    # rather than beside --config, so announcing from the repo root left a second cache at the root
    # holding the account id and owner email -- untracked, unignored, and dirtying the tree after
    # every release. --config is kept so the call still states what it targets.
    Push-Location (Split-Path $WORKER_CONFIG -Parent)
    try {
        & wrangler d1 execute $TELEMETRY_DB --remote --config $WORKER_CONFIG --command $sql
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) {
        # The build IS up and tagged at this point, so this is recoverable rather than fatal to what
        # already happened -- and re-running the whole script would re-export for one statement.
        Write-Host ""
        Write-Host ("The build is up and tagged, but the announce failed - nobody's game knows" +
                    " about $tag yet. Re-run just this:") -ForegroundColor Yellow
        Write-Host "  wrangler d1 execute $TELEMETRY_DB --remote --config $WORKER_CONFIG --command `"$sql`""
        throw "wrangler exited $LASTEXITCODE"
    }
}

$size = [Math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ""
Write-Host ("Built $tag in {0:N0}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "  $zip  (${size} MB, $($files.Count) files)"
Write-Host "  tagged $tag at $branch @ $sha$(if ($NoPush -and -not $tagAtHead) { ' (not pushed)' })"
if ($NoUpload) {
    Write-Host "  NOT uploaded and NOT announced (-NoUpload)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Hand out that zip." -ForegroundColor Green
} else {
    Write-Host "  pushed to $ITCH_TARGET, announced as the newest build"
    Write-Host ""
    Write-Host "It is live. Anyone on an older build gets told on their next launch." -ForegroundColor Green
}
