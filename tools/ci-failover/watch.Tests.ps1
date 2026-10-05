# watch.Tests.ps1 - the failover watcher's decision, tested with fixtures (Pester 3.4, which ships with
# Windows). Only Get-FailoverActions is under test: it is pure, so every case states a board of runs,
# runners and saved state and asserts what the watcher would do. Nothing here calls gh or touches a
# scheduled task. CI never runs this; run it locally:
#   powershell -NoProfile -Command "Invoke-Pester -Script tools\ci-failover\watch.Tests.ps1"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\watch.ps1"

$TheRepo = 'Phaazoid/Godoiosis'
$Now = [datetime]::Parse('2026-10-05T21:00:00Z', [Globalization.CultureInfo]::InvariantCulture,
	[Globalization.DateTimeStyles]::AdjustToUniversal)

function At([double]$minutesAgo) {
	return $Now.AddMinutes(-$minutesAgo).ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function New-Job {
	param(
		$Status = 'completed', $Conclusion = 'success', $Labels = @('ubuntu-latest'),
		$Runner = 'GitHub Actions 1000004305', [double]$CreatedAgo = 10, $CompletedAgo = 5, [int]$Steps = 15
	)
	$completed = $null
	if ($null -ne $CompletedAgo) { $completed = At $CompletedAgo }
	$stepList = @()
	if ($Steps -gt 0) { $stepList = @(1..$Steps) }
	return [pscustomobject]@{
		status = $Status; conclusion = $Conclusion; labels = $Labels; runner_name = $Runner
		created_at = (At $CreatedAgo); completed_at = $completed; steps = $stepList
	}
}

# A hosted job no runner has picked up: queued, no runner, no steps.
function New-WaitingJob([double]$CreatedAgo, $Labels = @('ubuntu-latest')) {
	return New-Job -Status 'queued' -Conclusion $null -Labels $Labels -Runner '' -CreatedAgo $CreatedAgo -CompletedAgo $null -Steps 0
}

# A hosted job GitHub cancelled before any runner took it.
function New-StrandedJob([double]$CreatedAgo, [double]$CompletedAgo) {
	return New-Job -Conclusion 'cancelled' -Runner '' -CreatedAgo $CreatedAgo -CompletedAgo $CompletedAgo -Steps 0
}

function New-Run {
	param(
		$Id, $Branch = 'fix/1228-grounded-footprint', $Status = 'completed', $Conclusion = 'success',
		[double]$CreatedAgo = 10, $HeadRepo = $TheRepo, $Jobs = @()
	)
	return [pscustomobject]@{
		id = $Id; head_branch = $Branch; status = $Status; conclusion = $Conclusion
		created_at = (At $CreatedAgo); head_repository = [pscustomobject]@{ full_name = $HeadRepo }
		jobs = @($Jobs)
	}
}

function New-Runner([bool]$Busy = $false) {
	return [pscustomobject]@{ name = 'iosis-1'; status = 'online'; busy = $Busy }
}

function Decide {
	param($Runs = @(), $Runners = @(), [bool]$Keepalive = $false, $State = $null)
	if ($null -eq $State) { $State = @{ last_up = $Now.ToString('o') } }
	return Get-FailoverActions -Runs $Runs -Runners $Runners -KeepaliveRunning $Keepalive `
		-State $State -Now $Now -Repo $TheRepo -Config (New-FailoverConfig)
}

# The runners up for a failover, last busy $idleMinutes ago.
function Up-State([double]$IdleMinutes, $Reason = 'failover', [double]$UpFor = 30) {
	return @{
		up_by_watcher = $true; up_reason = $Reason; up_since = (At $UpFor)
		last_activity = (At $IdleMinutes); last_up = $Now.ToString('o')
	}
}


Describe 'failing over' {
	It 'fails over a PR run whose hosted job has waited past the threshold' {
		$run = New-Run -Id 1 -Status 'in_progress' -Conclusion $null -CreatedAgo 7 -Jobs @(
			(New-Job -CreatedAgo 7 -CompletedAgo 4),
			(New-WaitingJob 7))
		$d = Decide -Runs @($run)
		$d.FailOvers.Count | Should Be 1
		$d.FailOvers[0].Branch | Should Be 'fix/1228-grounded-footprint'
		$d.FailOvers[0].Reason | Should Be 'stuck'
		$d.FailOvers[0].Cancel | Should Be $true
		$d.FailOvers[0].Dispatch | Should Be $true
	}

	It 'fails over a stuck run on main' {
		$run = New-Run -Id 2 -Branch 'main' -Status 'in_progress' -Conclusion $null -CreatedAgo 8 -Jobs @(New-WaitingJob 8)
		$d = Decide -Runs @($run)
		$d.FailOvers.Count | Should Be 1
		$d.FailOvers[0].Branch | Should Be 'main'
	}

	It 'waits while a hosted job is only briefly queued' {
		$run = New-Run -Id 3 -Status 'in_progress' -Conclusion $null -CreatedAgo 3 -Jobs @(New-WaitingJob 3)
		(Decide -Runs @($run)).FailOvers.Count | Should Be 0
	}

	It 'never counts a job waiting for the LOCAL runners as stuck' {
		$run = New-Run -Id 4 -Status 'in_progress' -Conclusion $null -CreatedAgo 20 -Jobs @(New-WaitingJob 20 @('self-hosted'))
		(Decide -Runs @($run) -Runners @(New-Runner)).FailOvers.Count | Should Be 0
	}

	It 'never runs a branch from someone else''s copy of the repo' {
		$run = New-Run -Id 5 -Status 'in_progress' -Conclusion $null -CreatedAgo 9 -HeadRepo 'stranger/Godoiosis' -Jobs @(New-WaitingJob 9)
		$d = Decide -Runs @($run)
		$d.FailOvers.Count | Should Be 0
		$d.Skips.Count | Should Be 1
		($d.State.handled -contains '5') | Should Be $true
	}

	It 'dispatches a branch once even when two of its runs are stuck' {
		$a = New-Run -Id 6 -Status 'in_progress' -Conclusion $null -CreatedAgo 9 -Jobs @(New-WaitingJob 9)
		$b = New-Run -Id 7 -Status 'in_progress' -Conclusion $null -CreatedAgo 7 -Jobs @(New-WaitingJob 7)
		$d = Decide -Runs @($a, $b)
		$d.FailOvers.Count | Should Be 2
		@($d.FailOvers | Where-Object { $_.Dispatch }).Count | Should Be 1
		@($d.FailOvers | Where-Object { $_.Cancel }).Count | Should Be 2
	}

	It 'never acts on the same run twice' {
		$run = New-Run -Id 8 -Status 'in_progress' -Conclusion $null -CreatedAgo 9 -Jobs @(New-WaitingJob 9)
		$first = Decide -Runs @($run)
		$first.FailOvers.Count | Should Be 1
		(Decide -Runs @($run) -State $first.State).FailOvers.Count | Should Be 0
	}

	It 'ignores runs older than the look-back window' {
		$run = New-Run -Id 9 -Status 'in_progress' -Conclusion $null -CreatedAgo 400 -Jobs @(New-WaitingJob 400)
		(Decide -Runs @($run)).FailOvers.Count | Should Be 0
	}
}

Describe 'a run GitHub already gave up on' {
	# The shape of #1231's run (37371291625): four shards passed, two sat queued 15 minutes with no
	# runner and were cancelled, and the run concluded FAILURE rather than cancelled.
	It 're-runs a timed-out run locally, even when the run concluded failure' {
		$run = New-Run -Id 10 -Conclusion 'failure' -CreatedAgo 30 -Jobs @(
			(New-Job -CreatedAgo 30 -CompletedAgo 27),
			(New-StrandedJob 30 15))
		$d = Decide -Runs @($run)
		$d.FailOvers.Count | Should Be 1
		$d.FailOvers[0].Reason | Should Be 'timed-out'
		$d.FailOvers[0].Cancel | Should Be $false
		$d.FailOvers[0].Dispatch | Should Be $true
	}

	It 'ignores a PR run cancelled seconds in because a newer push replaced it' {
		$run = New-Run -Id 11 -Conclusion 'cancelled' -CreatedAgo 10 -Jobs @(New-StrandedJob 10 9.9)
		(Decide -Runs @($run)).FailOvers.Count | Should Be 0
	}

	It 'leaves a timed-out run alone once the branch has run again' {
		$old = New-Run -Id 12 -Conclusion 'failure' -CreatedAgo 40 -Jobs @(New-StrandedJob 40 25)
		$rerun = New-Run -Id 13 -CreatedAgo 20 -Jobs @()
		(Decide -Runs @($old, $rerun)).FailOvers.Count | Should Be 0
	}

	It 'ignores a job that ran and failed for real' {
		$run = New-Run -Id 14 -Conclusion 'failure' -CreatedAgo 30 -Jobs @(
			(New-Job -Conclusion 'failure' -CreatedAgo 30 -CompletedAgo 10))
		(Decide -Runs @($run)).FailOvers.Count | Should Be 0
	}
}

Describe 'failing back' {
	It 'takes the runners down after ten idle minutes' {
		$d = Decide -Keepalive $true -Runners @(New-Runner) -State (Up-State 11)
		$d.BringDown | Should Not BeNullOrEmpty
	}

	It 'keeps them up inside the idle window' {
		(Decide -Keepalive $true -Runners @(New-Runner) -State (Up-State 5)).BringDown | Should BeNullOrEmpty
	}

	It 'never takes them down while a runner is busy' {
		$d = Decide -Keepalive $true -Runners @(New-Runner $true) -State (Up-State 30)
		$d.BringDown | Should BeNullOrEmpty
	}

	It 'never takes them down while a local job is still queued' {
		$run = New-Run -Id 20 -Status 'in_progress' -Conclusion $null -CreatedAgo 2 -Jobs @(New-WaitingJob 2 @('self-hosted'))
		$d = Decide -Runs @($run) -Keepalive $true -Runners @(New-Runner) -State (Up-State 30)
		$d.BringDown | Should BeNullOrEmpty
	}

	It 'never takes down runners the dev brought up by hand' {
		$state = @{ up_by_watcher = $false; last_activity = (At 60); last_up = $Now.ToString('o') }
		(Decide -Keepalive $true -Runners @(New-Runner) -State $state).BringDown | Should BeNullOrEmpty
	}
}

Describe 'keeping the runners registered' {
	It 'brings them up after ten days offline' {
		$state = @{ last_up = $Now.AddDays(-11).ToString('o') }
		(Decide -State $state).Heartbeat | Should Be $true
	}

	It 'leaves them down before then' {
		$state = @{ last_up = $Now.AddDays(-9).ToString('o') }
		(Decide -State $state).Heartbeat | Should Be $false
	}

	It 'starts the clock on first run rather than topping up at once' {
		$d = Decide -State @{}
		$d.Heartbeat | Should Be $false
		$d.State.last_up | Should Not BeNullOrEmpty
		$d.State.handled.Count | Should Be 0
	}

	It 'takes them down three minutes into a top-up' {
		(Decide -Keepalive $true -Runners @(New-Runner) -State (Up-State 4 'heartbeat' 4)).BringDown | Should Not BeNullOrEmpty
		(Decide -Keepalive $true -Runners @(New-Runner) -State (Up-State 1 'heartbeat' 1)).BringDown | Should BeNullOrEmpty
	}

	It 'turns a top-up into a failover window when a run gets stuck during it' {
		$run = New-Run -Id 30 -Status 'in_progress' -Conclusion $null -CreatedAgo 7 -Jobs @(New-WaitingJob 7)
		$d = Decide -Runs @($run) -Keepalive $true -Runners @(New-Runner) -State (Up-State 1 'heartbeat' 1)
		$d.FailOvers.Count | Should Be 1
		$d.State.up_reason | Should Be 'failover'
		$d.BringDown | Should BeNullOrEmpty
	}
}

Describe 'a healthy day' {
	It 'does nothing at all' {
		$runs = @(
			(New-Run -Id 40 -CreatedAgo 30 -Jobs @(New-Job -CreatedAgo 30 -CompletedAgo 25)),
			(New-Run -Id 41 -Branch 'main' -CreatedAgo 60))
		$d = Decide -Runs $runs
		$d.FailOvers.Count | Should Be 0
		$d.Skips.Count | Should Be 0
		$d.BringDown | Should BeNullOrEmpty
		$d.Heartbeat | Should Be $false
	}
}
