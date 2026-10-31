# CI shards

The Tests workflow (`.github/workflows/tests.yml`) splits the suite across five numbered shards plus `export`. This folder decides which suites each numbered shard runs.

Until 2026-10-31 the shards were cut by hand along folder lines. Two months after their last re-cut, one shard carried 384s of tests and another 96s, so the slowest job set the wall clock while the rest sat idle. Now the shards are **dealt** from recorded times, so they stay even as tests are added.

## How a shard gets its suites

Every numbered job runs `deal.sh`, which:

1. lists every `.gd` under `tests/`, except `tests/export/` (the `export` shard's own) and any folder holding a `.gdignore`;
2. weighs each file by its time in `times.tsv`. A file the table doesn't list, such as a new suite or a helper in `tests/support/`, counts as 1s;
3. deals them largest first, each to the lightest shard so far;
4. prints its own shard's files, which the workflow turns into one `-a` each.

Helpers are dealt too, on purpose. gdUnit4 decides what a suite is, and an `-a` naming a helper runs nothing. That makes the dealt set exactly what `-a res://tests` would have scanned.

Every job deals the whole hand itself. The deal is deterministic (integer milliseconds, ties broken by path), so the jobs agree without talking to each other. `deal.sh` refuses to print anything unless the shards cover every file exactly once: a shard that silently stops covering a suite stays green, so this is the check that catches it.

## When to refresh the times

The step summary on every run lists each shard's cases, suites and seconds. When the numbered shards' seconds spread apart, refresh the table:

```
bash tools/ci-shards/refresh.sh
```

It reads the last five successful runs of Tests on `main` (`gh`, signed in) and writes each suite's median time to `times.tsv`. A suite's time is the wall clock from its `Run Test Suite:` log line to the next. The median matters because each job runs on its own VM, and one run's shards have measured up to 1.5× slower than another's. Commit the new table like any other change.

CI never writes the table, so nothing re-dirties the tree.

## Changing the number of shards

The count lives in two places in `tests.yml`, and both must change together:

- `TEST_BUCKETS`
- the numbered entries of the matrix

Every numbered job checks that the two agree before it tests anything, and fails if they don't.

## Files

| File | What |
|---|---|
| `deal.sh` | Deals the shards. Called by `tests.yml`. |
| `deal-test.sh` | Checks `deal.sh`; run it after any change there. `DEAL_SCRIPT=<path>` points it at another script, to prove a case can go red. |
| `refresh.sh` | Rewrites `times.tsv` from CI logs. |
| `times.tsv` | Seconds per suite. Generated; don't hand-edit. |
| `.gdignore` | Keeps Godot out of this folder, so the import never makes a sidecar for `times.tsv`. |
