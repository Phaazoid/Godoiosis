# CI failover

When GitHub's hosted runners stop taking Tests jobs, this re-runs Tests on the three local runners (`iosis-1/2/3`, Ubuntu in WSL2 on the dev's machine). Once those runners have been idle for a while, it takes them offline again.

It exists because of the 2026-10-05 Actions outage. That outage broke only hosted-runner *assignment*: two of #1231's shards sat queued for 15 minutes and were cancelled without running a step, while the local runners were fine.

## Install

The dev runs this. It's the step that lets the machine take CI work on its own, so no agent runs it.

```
powershell -ExecutionPolicy Bypass -File tools\ci-failover\install.ps1
```

It does three things:

- copies `watch.ps1` to `%LOCALAPPDATA%\Iosis\ci-failover\`, so switching branches can't change the running script;
- registers the logon task **Iosis CI failover watcher**;
- starts the task.

Re-run it after pulling a new `watch.ps1`. `-Uninstall` removes the task.

It needs `gh` on PATH, signed in as an account that can dispatch workflows, and the existing **Iosis CI runners (WSL)** task. That task should stay **Disabled**: the watcher enables it when it needs the runners.

## What a failover looks like

The watcher checks every 2 minutes. It looks at Tests runs from the last 3 hours and finds one of two things.

- **Stuck:** a job on GitHub's image has been queued for 6 minutes or more. The watcher cancels that run and dispatches a fresh one on the same branch with `-f runner=local`.
- **Timed out:** a run already finished, and one of its hosted jobs was cancelled after about 15 minutes with no runner and no steps. This is the outage's signature, and the run concludes `failure` when other shards passed. The watcher dispatches a fresh run, unless the branch has already run again since.
  - A PR run cancelled because a newer push replaced it has the same no-runner signature, but it dies within seconds, so it's ignored.

After a successful dispatch, it enables and starts the keepalive task, which brings the runners up. They're ready about 75 seconds later, and the queued jobs start.

Once nothing has run or waited locally for 10 minutes, and no runner is busy, the watcher stops and disables the keepalive. The WSL VM then shuts itself down about 15 seconds later. It never does this while a runner is busy, because shutting WSL down cancels the job in flight. It also only takes down runners it brought up itself: if you start the keepalive by hand, it's yours.

The watcher shows a Windows notification:

- when it fails over;
- when the runners go back offline after a failover;
- when a dispatch fails.

**Registration top-up.** GitHub deletes a runner after 14 days offline. If the runners haven't been up for 10 days, the watcher brings them up for about 3 minutes and back down.

## Security

The repo is public, so **the fence is the runners being offline**, not the workflow file. A pull request from someone else's copy of the repo brings its own copy of `tests.yml` and can ask for `self-hosted` directly. Three things keep a stranger's code off this machine:

- The runners are online only during a failover or a top-up.
- The repo requires approval before *any* outside contributor's workflow runs (Settings → Actions → "Require approval for all external contributors").
- The watcher never dispatches a branch that lives in someone else's copy of the repo. Those runs are logged as skipped.

Only someone with write access can dispatch a run, so `runner: local` can't be requested from outside.

## Files

| Where | What |
|---|---|
| `%LOCALAPPDATA%\Iosis\ci-failover\watch.log` | Every decision, timestamped. Rotates to `watch.log.1` past 1 MB. |
| `%LOCALAPPDATA%\Iosis\ci-failover\state.json` | Runs already handled, and whether the watcher has the runners up. Delete it to start fresh. |

## Trying it

```
powershell -ExecutionPolicy Bypass -File tools\ci-failover\watch.ps1 -Once -DryRun
```

This runs one check against the live repo and logs what it *would* do, without acting. Every threshold is a parameter (`-StuckMinutes`, `-IdleMinutes`, and so on), so `-Once -StuckMinutes 0` fails over on demand.

The decision is one pure function, `Get-FailoverActions`, tested with fixtures by `watch.Tests.ps1` (Pester 3.4, which ships with Windows). CI never runs these tests.

```
powershell -NoProfile -Command "Invoke-Pester -Script tools\ci-failover\watch.Tests.ps1"
```

## Limits

- **A branch made before the `runner` input existed can't be dispatched this way.** GitHub refuses with HTTP 422, "Unexpected inputs provided". The watcher logs it and notifies you; rerun that run by hand once GitHub recovers.
- **The local run tests the branch's own head commit.** A `pull_request` run tests the merge of the branch into `main`.
- **Any open WSL session keeps the distro up.** A WSL terminal of your own keeps the runners online too. That's normal, but it means they're reachable while it stays open.
