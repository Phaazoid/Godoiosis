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

  NOTHING HERE IS TYPED TWICE. The engine comes from $env:GODOT_BIN exactly as tests\run_tests.ps1
  reads it, the version from project.godot (Build.version()'s one store), and the export path and
  the build's own name from export_presets.cfg - so an editor export and a scripted one land in the
  same place by construction rather than by agreement.

  Usage:
    powershell -File tools\archive-build.ps1            # export, zip, tag, push the tag
    powershell -File tools\archive-build.ps1 -NoPush    # everything but the push
#>

param(
    [switch]$NoPush
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent

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

$version = Read-Setting (Join-Path $root 'project.godot') '^config/version="(.+)"$' 'application/config/version'
$exportPath = Read-Setting (Join-Path $root 'export_presets.cfg') '^export_path="(.+)"$' 'an export_path'

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

# ---- 5. the export -----------------------------------------------------------------------------
# Two Godots on one project directory is already this project's normal - the export smoke spawns
# exactly this from inside a running engine, and run_tests.ps1 drives one while the editor is open.

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Write-Host "Exporting $name $tag ($branch @ $sha)..." -ForegroundColor Cyan

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $bin --headless --path $root --export-debug "Windows Desktop" $exe
$exportCode = $LASTEXITCODE
$sw.Stop()

if ($exportCode -ne 0) { throw "Godot exited $exportCode - no zip written, no tag created." }

# Godot has been known to exit 0 having written nothing useful, so the artifact is checked rather
# than inferred from the exit code.
foreach ($required in @($exe, $pck)) {
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
# FLAT - the three files at the zip's root, no folder inside. Compress-Archive on Windows PowerShell
# writes a folder's entries with backslash separators, which some extractors unpack as one file with
# a strange name; handing it a file list sidesteps that, and Extract All makes the folder anyway.

$files = @($exe, $pck)
if (Test-Path $console) { $files += $console }
Compress-Archive -Path $files -DestinationPath $zip -Force

# ---- 7. the tag, last --------------------------------------------------------------------------

if (-not $tagAtHead) {
    Invoke-Git @('tag', '-a', $tag, '-m', "Build $tag -- $branch @ $sha") | Out-Null
    if ($NoPush) {
        Write-Host "Tagged $tag locally. Push it with: git push origin $tag" -ForegroundColor Yellow
    } else {
        Invoke-Git @('push', 'origin', $tag) | Out-Null
    }
}

$size = [Math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ""
Write-Host ("Built $tag in {0:N0}s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "  $zip  (${size} MB, $($files.Count) files)"
Write-Host "  tagged $tag at $branch @ $sha$(if ($NoPush -and -not $tagAtHead) { ' (not pushed)' })"
Write-Host ""
Write-Host "Hand out that zip." -ForegroundColor Green
