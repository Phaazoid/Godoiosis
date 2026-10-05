<#
  install.ps1 - starts the CI failover watcher (watch.ps1) at every logon, hidden. -Uninstall removes it.

  THE DEV RUNS THIS, never an agent: it is the step that lets this machine take CI work on its own.

  The watcher runs from a COPY under %LOCALAPPDATA%\Iosis\ci-failover, so switching branches in a
  checkout cannot change or delete the script a running watcher is executing. Re-run this after
  pulling a new watch.ps1 to pick it up.

    powershell -ExecutionPolicy Bypass -File tools\ci-failover\install.ps1
    powershell -ExecutionPolicy Bypass -File tools\ci-failover\install.ps1 -Uninstall
#>
param([switch]$Uninstall)

$TaskName = 'Iosis CI failover watcher'
$KeepaliveTask = 'Iosis CI runners (WSL)'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Iosis\ci-failover'
$Installed = Join-Path $InstallDir 'watch.ps1'
$StatePath = Join-Path $InstallDir 'state.json'
$Source = Join-Path $PSScriptRoot 'watch.ps1'

if ($Uninstall) {
	$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
	if ($null -eq $task) {
		Write-Host "'$TaskName' is not installed."
	} else {
		Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
		Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
		Write-Host "Removed '$TaskName'."
	}
	Remove-Item -Force $Installed -ErrorAction SilentlyContinue

	# If the watcher had the runners up, nothing will take them down now, and an enabled keepalive
	# comes back at every logon. Disable it so it cannot, but do not stop it: a job may be running.
	if (Test-Path $StatePath) {
		$state = Get-Content $StatePath -Raw | ConvertFrom-Json
		if ($state.up_by_watcher) {
			Disable-ScheduledTask -TaskName $KeepaliveTask -ErrorAction SilentlyContinue | Out-Null
			Write-Warning ("The watcher had the local runners up. '$KeepaliveTask' is now disabled so they " +
				"will not return at logon, but it is still running. Once no CI job is running, stop it with:`n" +
				"  Stop-ScheduledTask -TaskName '$KeepaliveTask'")
		}
	}
	Write-Host "The log and state stay in $InstallDir."
	return
}

if (-not (Test-Path $Source)) { throw "watch.ps1 not found beside this script ($Source)." }
if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
	throw 'gh is not on PATH. The watcher needs the GitHub CLI, signed in as an account that can dispatch Tests.'
}
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw "gh is not signed in. Run 'gh auth login' first." }

$keepalive = Get-ScheduledTask -TaskName $KeepaliveTask -ErrorAction SilentlyContinue
if ($null -eq $keepalive) {
	Write-Warning ("'$KeepaliveTask' does not exist, so the watcher cannot bring the runners up. It would " +
		"still notice a stuck run and dispatch it, but the local run would wait for runners that never come.")
} elseif ("$($keepalive.State)" -ne 'Disabled') {
	Write-Warning ("'$KeepaliveTask' is $($keepalive.State), not Disabled, so the runners come up at every logon " +
		"whether or not there is failover work. The watcher only takes down runners it brought up itself.")
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Force $Source $Installed

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
	-Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Installed`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
	-RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) `
	-MultipleInstances IgnoreNew -StartWhenAvailable

# A re-install replaces the task, so stop the old loop first or it keeps running the old copy.
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
	-Settings $settings -Force `
	-Description 'Iosis: when GitHub''s hosted runners stall on Tests, re-runs it on the local WSL runners (tools/ci-failover).' |
	Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "Installed '$TaskName' and started it. It checks GitHub every 2 minutes."
Write-Host "Log: $(Join-Path $InstallDir 'watch.log')"
