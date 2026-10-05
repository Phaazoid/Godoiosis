<#
  watch.ps1 - CI failover. When GitHub's hosted runners stop taking Tests jobs, run them on the
  dev's local WSL runners instead, then take those runners offline again once they go idle.

  WHY (2026-10-05). GitHub had an outage in HOSTED-RUNNER ASSIGNMENT: #1231's dev and ui-flow shards
  sat queued and were cancelled after 15 minutes without running a step. The three self-hosted
  runners (iosis-1/2/3, Ubuntu in WSL2) were unaffected, but they are offline on purpose while the
  repo is public.

  GITHUB HAS NO FALLBACK RUNNER. A job's runner is fixed when the job is created, so a stuck job can
  never be moved. This cancels the stuck run and DISPATCHES a fresh one with `-f runner=local`, which
  tests.yml turns into `runs-on: self-hosted`. No repo variable is ever flipped, so there is nothing
  global to restore afterwards.

  THE FENCE IS THE RUNNERS BEING ONLINE, NOT THE WORKFLOW FILE. A pull request from someone else's
  copy of the repo carries its own workflow and can ask for `self-hosted` whenever the runners are
  listening. So the runners come up only while failover work needs them, and go down after
  -IdleMinutes of nothing. The repo's rule that every outside contributor's run waits for approval
  covers that window. A branch from someone else's copy is NEVER dispatched here.

  THE KEEPALIVE TASK IS THE ON/OFF SWITCH. The runners live in a WSL distro that idles out when no
  wsl.exe client is attached; `Iosis CI runners (WSL)` holds one open. Enabling and starting it
  brings the runners up (~75 s: the runner units carry a 60 s cold-start delay); stopping and
  disabling it lets the distro idle out. Never while a runner is busy: shutting WSL down cancels a
  job in flight.

  REGISTRATION TOP-UP. GitHub deletes a runner after 14 days offline, so if the runners have not been
  up for -HeartbeatDays the watcher brings them up for -HeartbeatMinutes and back down.

  THE DECISION IS ONE PURE FUNCTION, Get-FailoverActions, tested by watch.Tests.ps1 with fixtures.
  Everything around it is I/O: gh for GitHub, Task Scheduler for the switch.

  Usage (install.ps1 registers the loop at logon):
    powershell -File tools\ci-failover\watch.ps1 -Once -DryRun    # one check, decisions logged only
    powershell -File tools\ci-failover\watch.ps1 -Once            # one check, acting on it
    powershell -File tools\ci-failover\watch.ps1                  # the loop
#>
param(
	[switch]$Once,
	[switch]$DryRun,
	[string]$Repo = 'Phaazoid/Godoiosis',
	[int]$IntervalSeconds = 120,
	[double]$StuckMinutes = 6,
	[double]$TimedOutMinutes = 14,
	[double]$MaxAgeHours = 3,
	[double]$IdleMinutes = 10,
	[double]$HeartbeatDays = 10,
	[double]$HeartbeatMinutes = 3
)

$KeepaliveTask = 'Iosis CI runners (WSL)'
$StateDir = Join-Path $env:LOCALAPPDATA 'Iosis\ci-failover'
$StatePath = Join-Path $StateDir 'state.json'
$LogPath = Join-Path $StateDir 'watch.log'
$GhErrPath = Join-Path $StateDir 'gh-stderr.txt'
$LogCapBytes = 1MB


# --- pure helpers ---------------------------------------------------------------------------------

function New-FailoverConfig {
	param(
		[double]$StuckMinutes = 6,
		[double]$TimedOutMinutes = 14,
		[double]$MaxAgeHours = 3,
		[double]$IdleMinutes = 10,
		[double]$HeartbeatDays = 10,
		[double]$HeartbeatMinutes = 3,
		[int]$HandledCap = 200
	)
	return @{
		StuckMinutes = $StuckMinutes; TimedOutMinutes = $TimedOutMinutes; MaxAgeHours = $MaxAgeHours
		IdleMinutes = $IdleMinutes; HeartbeatDays = $HeartbeatDays; HeartbeatMinutes = $HeartbeatMinutes
		HandledCap = $HandledCap
	}
}

# PowerShell 5.1's ConvertFrom-Json leaves ISO timestamps as strings; 7 converts them. Both land here.
function ConvertTo-UtcTime($value) {
	if ($null -eq $value -or "$value" -eq '') { return $null }
	if ($value -is [datetime]) { return $value.ToUniversalTime() }
	return [datetime]::Parse("$value", [Globalization.CultureInfo]::InvariantCulture,
		[Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
}

function Test-SelfHostedJob($job) {
	return @($job.labels) -contains 'self-hosted'
}

function Get-StepCount($job) {
	if ($null -eq $job.steps) { return 0 }
	return @($job.steps).Count
}

# A HOSTED job still waiting for a runner past the threshold: the outage's live signature.
function Test-StuckJob($job, [datetime]$now, [double]$stuckMinutes) {
	if (Test-SelfHostedJob $job) { return $false }
	if ($job.status -ne 'queued') { return $false }
	$created = ConvertTo-UtcTime $job.created_at
	return $null -ne $created -and ($now - $created).TotalMinutes -ge $stuckMinutes
}

# A HOSTED job GitHub gave up on: cancelled with no runner and no steps, after waiting about 15
# minutes. A PR run cancelled because a newer push replaced it has the same no-runner signature but
# dies within seconds, and the wait threshold is what tells the two apart.
function Test-TimedOutJob($job, [double]$timedOutMinutes) {
	if (Test-SelfHostedJob $job) { return $false }
	if ($job.conclusion -ne 'cancelled') { return $false }
	if ("$($job.runner_name)" -ne '') { return $false }
	if ((Get-StepCount $job) -gt 0) { return $false }
	$created = ConvertTo-UtcTime $job.created_at
	$completed = ConvertTo-UtcTime $job.completed_at
	if ($null -eq $created -or $null -eq $completed) { return $false }
	return ($completed - $created).TotalMinutes -ge $timedOutMinutes
}

# A finished run whose jobs are worth reading for the timed-out signature. FAILURE as well as
# cancelled, because a run where some shards passed and the stranded ones were cancelled concludes
# `failure` (measured on #1231's run, 2026-10-05).
function Test-FinishedRunWorthReading($run) {
	return $run.status -eq 'completed' -and ($run.conclusion -eq 'cancelled' -or $run.conclusion -eq 'failure')
}

# Is anything running, or waiting to run, on the local runners right now?
function Test-LocalActive($runs, $runners) {
	foreach ($runner in @($runners)) {
		if ($null -ne $runner -and $runner.busy) { return $true }
	}
	foreach ($run in @($runs)) {
		foreach ($job in @($run.jobs)) {
			if ($null -eq $job) { continue }
			if ((Test-SelfHostedJob $job) -and ($job.status -eq 'queued' -or $job.status -eq 'in_progress')) {
				return $true
			}
		}
	}
	return $false
}


# --- THE DECISION ---------------------------------------------------------------------------------
#
# Runs: workflow runs from the API, each with a `jobs` array attached and `head_repository` as the API
# gives it. Runners: the repo's runners (name, status, busy). KeepaliveRunning: whether the switch is
# on. State: what earlier checks did (handled run ids, whether THIS watcher brought the runners up).
#
# Returns the actions to take and the state to keep. It never brings down runners it did not bring
# up: a keepalive started by hand is the dev's.
function Get-FailoverActions {
	param(
		[object[]]$Runs,
		[object[]]$Runners,
		[bool]$KeepaliveRunning,
		[hashtable]$State,
		[datetime]$Now,
		[string]$Repo,
		[hashtable]$Config
	)
	if ($null -eq $State) { $State = @{} }
	$state = @{
		handled = @($State.handled | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
		up_by_watcher = [bool]$State.up_by_watcher
		up_reason = $State.up_reason
		up_since = $State.up_since
		last_activity = $State.last_activity
		last_up = $State.last_up
	}
	if ($null -eq $state.last_up) { $state.last_up = $Now.ToString('o') }

	$failovers = New-Object System.Collections.ArrayList
	$skips = New-Object System.Collections.ArrayList
	$branchesDispatched = @{}
	$runs = @($Runs | Where-Object { $null -ne $_ })

	foreach ($run in $runs) {
		$id = "$($run.id)"
		if ($state.handled -contains $id) { continue }
		$created = ConvertTo-UtcTime $run.created_at
		if ($null -eq $created -or ($Now - $created).TotalHours -gt $Config.MaxAgeHours) { continue }
		$jobs = @($run.jobs | Where-Object { $null -ne $_ })

		$reason = $null
		if ($run.status -ne 'completed') {
			foreach ($job in $jobs) {
				if (Test-StuckJob $job $Now $Config.StuckMinutes) { $reason = 'stuck'; break }
			}
		} elseif (Test-FinishedRunWorthReading $run) {
			foreach ($job in $jobs) {
				if (Test-TimedOutJob $job $Config.TimedOutMinutes) { $reason = 'timed-out'; break }
			}
			if ($null -ne $reason) {
				# Somebody already ran this branch again after it (a rerun or a newer push): theirs stands.
				$newer = @($runs | Where-Object {
					$_.head_branch -eq $run.head_branch -and "$($_.id)" -ne $id -and
					(ConvertTo-UtcTime $_.created_at) -gt $created })
				if ($newer.Count -gt 0) { $reason = $null }
			}
		}
		if ($null -eq $reason) { continue }

		$headRepo = $null
		if ($null -ne $run.head_repository) { $headRepo = $run.head_repository.full_name }
		if ($headRepo -ne $Repo) {
			[void]$skips.Add(@{ RunId = $id; Why = "branch from another copy of the repo ($headRepo), never run locally" })
			$state.handled += $id
			continue
		}
		$branch = "$($run.head_branch)"
		$dispatch = -not $branchesDispatched.ContainsKey($branch)
		$branchesDispatched[$branch] = $true
		[void]$failovers.Add(@{
			RunId = $id
			Branch = $branch
			Reason = $reason
			Cancel = ($run.status -ne 'completed')
			Dispatch = $dispatch
		})
		$state.handled += $id
	}
	if ($state.handled.Count -gt $Config.HandledCap) {
		$state.handled = @($state.handled | Select-Object -Last $Config.HandledCap)
	}

	$localActive = Test-LocalActive $runs $Runners
	if ($localActive -or $failovers.Count -gt 0) { $state.last_activity = $Now.ToString('o') }
	if ($KeepaliveRunning) { $state.last_up = $Now.ToString('o') }
	# A failover arriving while a registration top-up has the runners up makes it a failover window,
	# or the top-up's short timer would take the runners down under the work.
	if ($failovers.Count -gt 0 -and $state.up_by_watcher) { $state.up_reason = 'failover' }

	$bringDown = $null
	if ($state.up_by_watcher -and $failovers.Count -eq 0 -and -not $localActive) {
		if ($state.up_reason -eq 'heartbeat') {
			$since = ConvertTo-UtcTime $state.up_since
			if ($null -eq $since -or ($Now - $since).TotalMinutes -ge $Config.HeartbeatMinutes) {
				$bringDown = 'registration top-up done'
			}
		} else {
			$last = ConvertTo-UtcTime $state.last_activity
			if ($null -eq $last -or ($Now - $last).TotalMinutes -ge $Config.IdleMinutes) {
				$bringDown = "idle for $($Config.IdleMinutes) minutes"
			}
		}
	}

	$heartbeat = $false
	if (-not $KeepaliveRunning -and -not $state.up_by_watcher -and $failovers.Count -eq 0 -and -not $localActive) {
		$lastUp = ConvertTo-UtcTime $state.last_up
		if ($null -ne $lastUp -and ($Now - $lastUp).TotalDays -ge $Config.HeartbeatDays) { $heartbeat = $true }
	}

	return @{
		FailOvers = @($failovers)
		Skips = @($skips)
		BringDown = $bringDown
		Heartbeat = $heartbeat
		State = $state
	}
}


# --- I/O -------------------------------------------------------------------------------------------

function Write-Log([string]$message) {
	$line = '{0}  {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $message
	if ($DryRun) { $line = "[dry run] $line" }
	Write-Host $line
	try {
		if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt $LogCapBytes) {
			Move-Item -Force $LogPath "$LogPath.1"
		}
		Add-Content -Path $LogPath -Value $line -Encoding UTF8
	} catch { }
}

function Send-Notice([string]$title, [string]$body) {
	if ($DryRun) { return }
	try {
		[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
		$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
			[Windows.UI.Notifications.ToastTemplateType]::ToastText02)
		$texts = $xml.GetElementsByTagName('text')
		[void]$texts.Item(0).AppendChild($xml.CreateTextNode($title))
		[void]$texts.Item(1).AppendChild($xml.CreateTextNode($body))
		$app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
		[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show(
			[Windows.UI.Notifications.ToastNotification]::new($xml))
	} catch {
		Write-Log "notification failed: $($_.Exception.Message)"
	}
}

# stderr goes to a file, never into the JSON: a gh notice on stderr would otherwise break the parse.
function Invoke-GhJson([string]$path) {
	$raw = & gh api $path 2>$GhErrPath
	if ($LASTEXITCODE -ne 0) {
		$err = (Get-Content $GhErrPath -Raw -ErrorAction SilentlyContinue)
		throw "gh api $path failed (exit $LASTEXITCODE): $err"
	}
	return ($raw | Out-String | ConvertFrom-Json)
}

# "$_" turns a stderr ErrorRecord back into gh's own line, without PowerShell's NativeCommandError frame.
function Invoke-Gh([string[]]$arguments) {
	$out = (& gh @arguments 2>&1 | ForEach-Object { "$_" }) -join ' '
	return @{ Ok = ($LASTEXITCODE -eq 0); Output = $out.Trim() }
}

function Read-State {
	if (-not (Test-Path $StatePath)) { return @{} }
	try {
		$obj = Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
	} catch {
		Write-Log "state file unreadable, starting fresh: $($_.Exception.Message)"
		return @{}
	}
	$state = @{}
	foreach ($p in $obj.PSObject.Properties) { $state[$p.Name] = $p.Value }
	return $state
}

function Save-State([hashtable]$state) {
	if ($DryRun) { return }
	$state | ConvertTo-Json -Depth 4 | Set-Content -Path $StatePath -Encoding UTF8
}

function Test-KeepaliveRunning {
	$task = Get-ScheduledTask -TaskName $KeepaliveTask -ErrorAction SilentlyContinue
	return $null -ne $task -and "$($task.State)" -eq 'Running'
}

function Start-Runners {
	Enable-ScheduledTask -TaskName $KeepaliveTask | Out-Null
	Start-ScheduledTask -TaskName $KeepaliveTask
}

function Stop-Runners {
	Stop-ScheduledTask -TaskName $KeepaliveTask -ErrorAction SilentlyContinue
	Disable-ScheduledTask -TaskName $KeepaliveTask | Out-Null
	# Stopping the task ends its PowerShell loop, but the wsl.exe client that loop started can outlive
	# it, and that client is what keeps the distro up. So it goes too.
	Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" -ErrorAction SilentlyContinue |
		Where-Object { $_.CommandLine -like '*sleep infinity*' } |
		ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Get-RecentRuns([hashtable]$config) {
	$runs = @((Invoke-GhJson "repos/$Repo/actions/workflows/tests.yml/runs?per_page=30").workflow_runs)
	$now = (Get-Date).ToUniversalTime()
	foreach ($run in $runs) {
		$created = ConvertTo-UtcTime $run.created_at
		$recent = $null -ne $created -and ($now - $created).TotalHours -le $config.MaxAgeHours
		$jobs = @()
		if ($run.status -ne 'completed' -or ($recent -and (Test-FinishedRunWorthReading $run))) {
			$jobs = @((Invoke-GhJson "repos/$Repo/actions/runs/$($run.id)/jobs").jobs)
		}
		$run | Add-Member -NotePropertyName jobs -NotePropertyValue $jobs -Force
	}
	return $runs
}

function Invoke-Check {
	$config = New-FailoverConfig -StuckMinutes $StuckMinutes -TimedOutMinutes $TimedOutMinutes `
		-MaxAgeHours $MaxAgeHours -IdleMinutes $IdleMinutes -HeartbeatDays $HeartbeatDays `
		-HeartbeatMinutes $HeartbeatMinutes
	$runs = Get-RecentRuns $config
	$runners = @((Invoke-GhJson "repos/$Repo/actions/runners").runners)
	$keepalive = Test-KeepaliveRunning
	$now = (Get-Date).ToUniversalTime()
	$decision = Get-FailoverActions -Runs $runs -Runners $runners -KeepaliveRunning $keepalive `
		-State (Read-State) -Now $now -Repo $Repo -Config $config
	$next = $decision.State
	$acted = $false

	foreach ($skip in $decision.Skips) { Write-Log "run $($skip.RunId) skipped: $($skip.Why)" }

	$dispatched = New-Object System.Collections.ArrayList
	foreach ($f in $decision.FailOvers) {
		$acted = $true
		Write-Log "run $($f.RunId) on '$($f.Branch)' is $($f.Reason) on GitHub's runners"
		if ($DryRun) {
			Write-Log "would cancel it: $($f.Cancel); would dispatch '$($f.Branch)' with runner=local: $($f.Dispatch)"
			if ($f.Dispatch) { [void]$dispatched.Add($f.Branch) }
			continue
		}
		if ($f.Cancel) {
			$r = Invoke-Gh @('run', 'cancel', $f.RunId, '--repo', $Repo)
			if (-not $r.Ok) { Write-Log "cancel of $($f.RunId) failed, so it will time out on its own: $($r.Output)" }
		}
		if ($f.Dispatch) {
			$r = Invoke-Gh @('workflow', 'run', 'tests.yml', '--repo', $Repo, '--ref', $f.Branch, '-f', 'runner=local')
			if ($r.Ok) {
				Write-Log "dispatched Tests on '$($f.Branch)' to the local runners"
				[void]$dispatched.Add($f.Branch)
			} else {
				Write-Log "dispatch on '$($f.Branch)' FAILED (a branch older than the runner input cannot take it): $($r.Output)"
				Send-Notice 'CI stalled, local run failed' "Tests on '$($f.Branch)' is stuck on GitHub's runners and could not be sent to the local ones. See watch.log."
			}
		}
	}

	$why = $null
	if ($dispatched.Count -gt 0) { $why = 'failover' } elseif ($decision.Heartbeat) { $why = 'heartbeat' }
	if ($null -ne $why -and -not $keepalive) {
		$acted = $true
		Write-Log "bringing the local runners up ($why)"
		if (-not $DryRun) {
			Start-Runners
			$next.up_by_watcher = $true
			$next.up_reason = $why
			$next.up_since = $now.ToString('o')
			$next.last_up = $now.ToString('o')
		}
	}
	if ($dispatched.Count -gt 0) {
		Send-Notice 'CI failed over to the local runners' ("GitHub's runners stalled. Tests dispatched on: " + ($dispatched -join ', '))
	}

	if ($null -ne $decision.BringDown) {
		$acted = $true
		Write-Log "taking the local runners offline: $($decision.BringDown)"
		if (-not $DryRun) {
			$wasFailover = $next.up_reason -ne 'heartbeat'
			Stop-Runners
			$next.up_by_watcher = $false
			$next.up_reason = $null
			$next.up_since = $null
			if ($wasFailover) { Send-Notice 'Local CI runners offline' "Failover finished: $($decision.BringDown)." }
		}
	}

	if ($Once -and -not $acted) {
		Write-Log "nothing to do: $(@($runs).Count) recent Tests runs, none stuck; keepalive running: $keepalive"
	}
	Save-State $next
}


# --- entry -----------------------------------------------------------------------------------------
# Dot-sourcing (the tests) defines the functions and stops here.
if ($MyInvocation.InvocationName -eq '.') { return }

$env:GH_NO_UPDATE_NOTIFIER = '1'
$env:GH_PROMPT_DISABLED = '1'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
	Write-Log 'gh is not on PATH, so the watcher cannot see GitHub'
	exit 1
}
if ($Once) {
	Invoke-Check
	exit 0
}
Write-Log "watcher started (checking every $IntervalSeconds s)"
while ($true) {
	try { Invoke-Check } catch { Write-Log "check failed: $($_.Exception.Message)" }
	Start-Sleep -Seconds $IntervalSeconds
}
