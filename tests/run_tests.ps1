# One-command headless gdUnit4 runner for Iosis.
# Usage:   powershell -File tests\run_tests.ps1 [res://path]
#   (default runs the whole tests/ tree; pass a folder/suite to narrow)
# Override the engine with $env:GODOT_BIN if your Godot lives elsewhere.
param([string]$TestPath = "res://tests")

$bin = $env:GODOT_BIN
if (-not $bin) { $bin = "C:\Godot\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" }
if (-not (Test-Path $bin)) {
	Write-Error "Godot not found at '$bin'. Set `$env:GODOT_BIN to your Godot 4.6 console exe."
	exit 1
}

$root = Split-Path $PSScriptRoot -Parent
& $bin --path $root --headless -s "res://addons/gdUnit4/bin/GdUnitCmdTool.gd" -a $TestPath --ignoreHeadlessMode
exit $LASTEXITCODE
