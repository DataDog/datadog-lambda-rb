# TODO

- [ ] Fix 1 — Kill duplicate CI runs: change `.github/workflows/build.yml` `on: [push, pull_request]` → `on: [pull_request]`, and add `concurrency` to cancel superseded runs. Currently every check runs twice (8 unit-test, 8 integration-test, 2 lint on PR #165) — ~50% of CI time and AWS sandbox usage is wasted on duplicates.
  - Effort: trivial
  - Time saved per PR: ~50% of all CI wall-time + AWS cost
- [ ] Fix 2 — Honor `$ARCH` in `scripts/build_layers.sh`: the script hardcodes both arm64 + amd64 (lines 64–68) and never reads `$ARCH`. Integration-test jobs set `ARCH: amd64`, so the arm64 build (run via `qemu-user-static` emulation on amd64 host) is pure waste. `check-size` also builds 8 layers (4 runtimes × 2 arches) when only amd64 is needed.
  - Effort: small
  - Time saved per PR: ~40% of each Docker build (eliminates qemu arm64 emulation); likely the reason `check-size` stuck past 1h45m
- [ ] Fix 3 — Add buildx GHA caching: `scripts/build_layers.sh` uses `docker buildx build ... --no-cache` with no `--cache-from/--cache-to`. The Dockerfile reinstalls `datadog` (2.40), `ffi` from source, and `gcc/gcc-c++/make` every run. Add `--cache-to type=gha,mode=max` / `--cache-from type=gha` and drop `--no-cache` for PR builds (keep it for release/tagged builds).
  - Effort: small
  - Time saved per PR: ~30–60s/job on cache hit; more for apt + gem install layers
- [ ] Fix 4 — Build layers once, share as artifact: `check-size` and `integration-test` both run `build_layers.sh` independently (~8 Docker builds each). Refactor to build layers in a dedicated job, upload as workflow artifact, and have both `check-size` and `integration-test` download it. Collapses ~16 builds into ~4 (one per runtime).
  - Effort: medium (workflow refactor)
  - Time saved per PR: removes 8 redundant Docker builds; significant on warm cache
- [ ] Fix 5 — Poll CloudWatch logs instead of fixed `sleep 45`: `scripts/run_integration_tests.sh` hardcodes `LOGS_WAIT_SECONDS=45` then fetches logs with up to 10×10s retries. Replace the fixed sleep with polling the log stream until it appears.
  - Effort: small
  - Time saved per PR: up to 45s × 4 runtime jobs (~3min total)
- [ ] Fix 6 — Bump `check-size.yml` Node 14.15 → Node 20: `check-size.yml` uses `node-version: 14.15` (EOL since 2021) while `build.yml` already uses Node 20. Align to Node 20 for consistency and faster `yarn install`/`serverless`.
  - Effort: trivial
  - Time saved per PR: minor (tooling speed + flake reduction)

## Pipeline improvements (from 3.30.0 release retro — RELEASE_ISSUES_3.30.0.md)

- [ ] Fix 7 — Remove `me-south-1` from `.gitlab/datasources/regions.yaml`: the DC/region is no longer available, so all 8 `publish layer prod` jobs for `me-south-1` fail every release with `Failed to connect to proxy URL: "http://127.0.0.1:15002"`. Removing it stops 8 perpetual failures and clears the red pipeline status on every release.
  - Effort: trivial
  - Impact: removes 8 guaranteed failures per release; pipeline status reflects reality
- [ ] Fix 8 — Increase unsigned-artifact `expire_in` and/or auto-run `sign layer`: the template sets `expire_in: 1 hr` on unsigned layer zips, and `sign layer` jobs are manual, so an operator must click sign within 1 hour of the build or artifacts expire and the build must be re-run. Either lengthen `expire_in` (e.g. 1 day) or make `sign layer` auto-run after build+test (gated), reserving manual approval for `publish layer prod` only. Confirm in retro whether signing must stay manual (and why).
  - Effort: small (config) / medium (if changing job gating)
  - Impact: removes the sign-vs-expiry race that forced a full rebuild + re-sign on 3.30.0
- [ ] Fix 9 — Fix or remove `DDCI Status` check: it consistently fails on PRs but is marked "Not required to merge", creating noise on every PR. Either fix the DDCI integration so it's green, or stop reporting it as a check.
  - Effort: small (investigate)
  - Impact: reduces PR noise / false-alarm fatigue

## Docs improvements (Confluence "Lambda Layer Ruby" page — from 3.30.0 release retro)

- [x] Doc 1 — RC section: state that RC layers must publish to `us-west-2` (not `sa-east-1`) for e2e tests. The current "Manual Tests" section says `sa-east-1` "for speed", which misled the 3.30.0 RC.
  - ✅ Done in Confluence v35: RC step 1 now says "...to the `us-west-2` region. This region is required to run the e2e tests in the next step."
- [ ] Doc 2 — RC section: warn that omitting `LANGUAGES_SUBSET=ruby` tests all languages, dramatically increasing runtime and AWS throttling risk.
- [ ] Doc 3 — Note that per-region layer versions are independent counters; `1` in a fresh region (e.g. sa-east-1) is expected, not a bug.
- [ ] Doc 4 — Release section: prominently document the 1-hour sign deadline and that `sign layer` jobs are manual (and why), so operators don't lose artifacts by stepping away.
  - 🟡 Partial in Confluence v35: step 2 NOTE + step 5 NOTE both state the 1-hour deadline and that signing is manual. The *why* (why signing is manual at all) is still missing — pending the retro (see Fix 8 / Retro).
- [ ] Doc 5 — Release section: note `me-south-1` is unavailable and its publish failures are expected.
- [ ] Doc 6 — GovCloud section: document access/training prerequisites and how to verify access before starting the release (log into the govcloud Google profile and try to access AWS), so operators can refresh access in parallel with earlier steps instead of discovering lapsed access at step 6.
  - 🟡 Partial in Confluence v35: step 6 mentions gov cloud access + the `[profile sso-govcloud-us1-fed-engineering]` profile. Missing: yearly training currency + how to verify access before starting (log into the govcloud Google profile, try to access AWS).

## Process

- [ ] Retro — Schedule a retro on the rb release process (suggested by Rey, Slack #72). Use RELEASE_ISSUES_3.30.0.md as the agenda; determine whether `sign layer` can be automatic and whether manual approval should move to `publish layer prod` only.
