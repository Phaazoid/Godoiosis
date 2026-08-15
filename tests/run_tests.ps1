# One-command headless gdUnit4 runner for Iosis.
#
# Usage:
#   powershell -File tests\run_tests.ps1                   # the fast tier (default)
#   powershell -File tests\run_tests.ps1 weapons items     # one or more areas (folders under tests/)
#   powershell -File tests\run_tests.ps1 res://tests/ai    # explicit res:// path (back-compat)
#   powershell -File tests\run_tests.ps1 full              # the whole tree -- SEE BELOW, you probably want CI
#
# THE FULL TREE IS CI'S JOB, NOT YOURS (dev rule 2026-08-15; canon in CLAUDE.md).
# .github/workflows/tests.yml runs the whole suite on every push and PR, with the same #93 and
# #146 guards this script has, in ~127s on GitHub's machine while you get on with something else.
# A local full run duplicates that exactly and costs ~230s of YOUR machine that you sit through.
# So the bare invocation defaults to `fast`, not `full` -- the expensive option should take
# deliberate typing. Locally, prefer the narrowest AREA that loads the surface you touched.
#
# WHY TIERS EXIST -- measured 2026-07-24 over 573 cases / 79 suites (report_173):
# cost is ~0.10s per test case plus ~0.75s per suite FILE, and it is near-UNIFORM. The
# cheapest possible test (comparing two const arrays, no scene) costs 0.078s; the most
# expensive (loading every scenario off disk) costs 0.221s -- only 2.9x apart. That means
# there are no slow suites to quarantine: the only lever is running FEWER tests. Roughly
# half the full run's wall clock is fixed overhead, so a tier saves on both axes.
#
# Override the engine with $env:GODOT_BIN if your Godot lives elsewhere.

param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Targets)

# Named tiers -> folder names under tests/. An EMPTY list means "the whole tree".
# `fast` is the invariant core: the Law guards (registry completeness, AI action coverage,
# damage floor, DEF mitigation) plus the pure rule/math layers. It is the "did I break
# something cross-cutting" check, NOT a substitute for the full run before a commit.
$Tiers = @{
	'full' = @()
	'fast' = @('law', 'rules', 'stats', 'unit', 'util')
}

$bin = $env:GODOT_BIN
if (-not $bin) { $bin = "C:\Godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64_console.exe" }
if (-not (Test-Path $bin)) {
	Write-Error "Godot not found at '$bin'. Set `$env:GODOT_BIN to your Godot 4.7 console exe."
	exit 1
}

$root = Split-Path $PSScriptRoot -Parent
# Defaults to `fast`, NOT `full` -- see the header. An accidental bare invocation should cost
# seconds, not four minutes, and the full tree already has an owner (CI).
if (-not $Targets -or $Targets.Count -eq 0) { $Targets = @('fast') }

$folders = New-Object System.Collections.Generic.List[string]
$explicit = New-Object System.Collections.Generic.List[string]
$wholeTree = $false

foreach ($t in $Targets) {
	if ($t -like 'res://*') { $explicit.Add($t); continue }
	if ($Tiers.ContainsKey($t)) {
		if ($Tiers[$t].Count -eq 0) { $wholeTree = $true }
		else { foreach ($f in $Tiers[$t]) { $folders.Add($f) } }
		continue
	}
	$folders.Add($t)
}

# Fail loudly on a typo'd area rather than silently running nothing -- gdUnit4 treats an
# unknown -a path as "zero suites matched" and still exits 0, which reads as a clean pass.
$known = Get-ChildItem -Path $PSScriptRoot -Directory | Select-Object -ExpandProperty Name
foreach ($f in $folders) {
	if ($known -notcontains $f) {
		Write-Error "Unknown test area '$f'. Tiers: $($Tiers.Keys -join ', '). Areas: $($known -join ', ')."
		exit 1
	}
}

$paths = New-Object System.Collections.Generic.List[string]
if ($wholeTree) {
	$paths.Add('res://tests')
} else {
	foreach ($f in ($folders | Select-Object -Unique)) { $paths.Add("res://tests/$f") }
	foreach ($e in $explicit) { $paths.Add($e) }
}

# -a appends (GdUnitTestCIRunner.add_test_suite -> _included_tests.append), so it repeats.
$argv = @('--path', $root, '--headless', '-s', 'res://addons/gdUnit4/bin/GdUnitCmdTool.gd')
foreach ($p in $paths) { $argv += @('-a', $p) }
$argv += '--ignoreHeadlessMode'

if ($wholeTree) {
	Write-Host "NOTE: the full tree is CI's job (.github/workflows/tests.yml runs it on every push/PR" -ForegroundColor Yellow
	Write-Host "      in ~127s, off your machine). Locally, prefer the narrowest area folder." -ForegroundColor Yellow
}

Write-Host "Running: $($paths -join '  ')" -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $bin @argv | Tee-Object -Variable transcript
$procCode = $LASTEXITCODE
$sw.Stop()

# THE VERDICT IS gdUnit4'S, NOT THE PROCESS'S (#93). Godot can die with an access violation
# (0xC0000005 / -1073741819) while tearing the engine down, AFTER every test has already run
# and been accounted for -- so the process exit code reports failure on a clean pass. It is a
# gdUnit4 teardown bug, not ours: the same work driven by a plain `--script` SceneTree probe
# exits 0, and it reproduces from a four-line suite that touches no game state at all.
#
# So: parse gdUnit4's own reported verdict and exit with THAT. This is strictly more truthful
# than trusting the process, in both directions -- a real failure still prints "Exit code: 100"
# and is still reported, and a crash that kills the run BEFORE gdUnit4 reports (no verdict line
# at all) is treated as a hard failure rather than being papered over.
$verdict = $null
foreach ($line in $transcript) {
	if ($line -match 'Exit code:\s*(\d+)') { $verdict = [int]$Matches[1] }
}

if ($null -eq $verdict) {
	Write-Host ("Elapsed {0:N1}s  (process exit {1})" -f $sw.Elapsed.TotalSeconds, $procCode) -ForegroundColor Cyan
	Write-Error "gdUnit4 never reported a verdict -- the run died before finishing. Treating as FAILURE."
	if ($procCode -eq 0) { exit 1 }
	exit $procCode
}

# ...AND THE VERDICT ONLY MEANS ANYTHING IF TESTS ACTUALLY RAN (#146). A suite that fails to
# LOAD -- a parse error in a production class it depends on -- takes zero tests with it, and
# gdUnit4 then honestly reports "No test cases found" + "Exit code: 0", because nothing failed:
# nothing ran. The override above would discard the real non-zero process exit and call that a
# clean pass, which is how a broken `Unit`/`SquadManager`/`game.gd` could redden nothing at all.
#
# The #93 override's whole premise is "every test already ran and was counted" -- so REQUIRE
# that rather than assume it. Cases-executed is the discriminator because a #93 teardown crash
# happens AFTER reporting (so N > 0), while a load failure never gets there (no line, or 0).
# Chosen over matching the segfault exit code because this has to hold in bash for CI too.
$casesRan = $null
foreach ($line in $transcript) {
	if ($line -match 'Executed test cases\s*:\s*\((\d+)/(\d+)\)') { $casesRan = [int]$Matches[1] }
}

if ($null -eq $casesRan -or $casesRan -eq 0) {
	Write-Host ("Elapsed {0:N1}s  (gdUnit4 verdict {1}; process exit {2})" -f $sw.Elapsed.TotalSeconds, $verdict, $procCode) -ForegroundColor Cyan
	Write-Error "ZERO test cases executed -- a suite failed to load, or the target matched nothing. Treating as FAILURE (#146)."
	if ($procCode -eq 0) { exit 1 }
	exit $procCode
}

if ($procCode -ne $verdict) {
	Write-Host ("Elapsed {0:N1}s  (gdUnit4 verdict {1}; process exited {2})" -f $sw.Elapsed.TotalSeconds, $verdict, $procCode) -ForegroundColor Cyan
	Write-Host "NOTE: the engine crashed while shutting down, after all tests had run and been counted (#93)." -ForegroundColor Yellow
	Write-Host "      Test results above are unaffected. Reporting gdUnit4's verdict ($verdict)." -ForegroundColor Yellow
} else {
	Write-Host ("Elapsed {0:N1}s  (exit {1})" -f $sw.Elapsed.TotalSeconds, $verdict) -ForegroundColor Cyan
}
exit $verdict
