# datadog-lambda-rb 3.30.0 Release — Issues, Fixes & Improvements

**Release:** `datadog-lambda-rb` 3.30.0
**Date:** 2026-08-12 → 2026-08-14
**Operator:** Lucas Pimentel (first-time releaser for this repo)
**Slack thread:** https://dd.slack.com/archives/C0880PRMWG3/p1786544820017069
**Release doc (Confluence):** https://datadoghq.atlassian.net/wiki/spaces/SLS/pages/2723578786/Lambda+Layer+Ruby
**Version bump PR:** https://github.com/DataDog/datadog-lambda-rb/pull/165
**GitLab release pipeline:** https://gitlab.ddbuild.io/DataDog/datadog-lambda-rb/-/pipelines/131086473 (child of 131086285)

This is a retro-style log of every issue hit while running the 3.30.0 release, how each was
fixed, and concrete improvements for the pipeline and docs. Sources: the #apm-serverless Slack
thread, this agent session's history, and the Confluence release process page.

---

## Issues hit (chronological)

### 1. RC layers published to the wrong region for e2e tests
- **What:** Per the Confluence "Manual Tests" section ("we tend to publish it to `sa-east-1`
  for speed"), the RC layers were published to `sa-east-1`. But the `serverless-e2e-tests`
  pipeline needs the layers in `us-west-2`.
- **Fix:** Republished the RC layers to `us-west-2`; e2e tests then passed. (Slack msgs #13–15)
- **Impact:** Wasted a RC pipeline run + a manual AWS sign-in to retrieve ARNs.
- **Improvement (docs):** The Confluence "Release Candidate" section must state that RC layers
  must be published to `us-west-2` (not `sa-east-1`) because that's where e2e tests run. Rey
  also added a fast-fail check to the e2e pipeline (PR
  [serverless-e2e-tests#287](https://github.com/DataDog/serverless-e2e-tests/pull/287)).

### 2. RC layer version showed "1" (confusion, not a bug)
- **What:** Published layer version was `1` in `sa-east-1`, prompting "version 1?" concern.
- **Cause:** Nobody had published to `sa-east-1` before, so the version counter started at 1.
- **Fix:** None needed — expected behavior for a fresh region. (Slack #3, #8–12)
- **Improvement (docs):** Note that per-region layer versions are independent counters and will
  be `1` in regions that have never received the layer.

### 3. E2E tests: AWS Lambda throttling (`TooManyRequestsException: Rate exceeded`)
- **What:** The `invoke lambda-features` job failed with `TooManyRequestsException: Rate
  exceeded` on the Lambda `FunctionUpdated` waiter while resetting 222 functions. (Slack #30–31)
- **Fix:** Rey's PR
  [serverless-e2e-tests#289](https://github.com/DataDog/serverless-e2e-tests/pull/289) added
  adaptive retries and catches these waiter exceptions.
- **Improvement (pipeline):** Land #289; consider lowering the function count or adding
  concurrency limits in the e2e harness.

### 4. E2E pipeline started without `LANGUAGES_SUBSET=ruby`
- **What:** The `serverless-e2e-tests` pipeline was started without `LANGUAGES_SUBSET=ruby`,
  so it tested all languages → more resources → more throttling. (Slack #37–46)
- **Fix:** Canceled and restarted with `LANGUAGES_SUBSET=ruby`.
- **Improvement (docs):** The Confluence "Release Candidate" step 2 already lists
  `LANGUAGES_SUBSET=ruby`, but it should explicitly warn that omitting it tests all languages
  and dramatically increases throttling risk + runtime.

### 5. Duplicate CI runs (`push` + `pull_request` triggers)
- **What:** `.github/workflows/build.yml` has `on: [push, pull_request]`, so every PR check
  runs twice. On PR #165: 8 unit-test, 8 integration-test, 2 lint runs. ~50% of CI time and
  AWS sandbox cost is wasted on duplicates. (Slack #62; this session)
- **Fix:** Not yet applied. Planned in the `lpimentel/ci-reduce-runtime` branch (TODO Fix 1).
- **Improvement (pipeline):** Change to `on: [pull_request]` and add a `concurrency` group to
  cancel superseded runs. **Highest bang-for-buck, trivial effort.**

### 6. Integration tests are extremely slow (~45–50 min each)
- **What:** Each per-runtime integration-test job took 45–50 min. They are full AWS e2e tests,
  not just unit tests: build layers → `serverless deploy` → N×`serverless invoke` → `sleep 45`
  → M×`serverless logs` (up to 10×10s retries) → `serverless remove`. (Slack #54–57; this session)
- **Root causes (this session's investigation):**
  - `scripts/build_layers.sh` ignores `$ARCH` and always builds **both arm64 + amd64**; the
    arm64 build runs via `qemu-user-static` emulation on an amd64 host (slow).
  - `docker buildx build ... --no-cache` with no `--cache-from/--cache-to` → apt + gem install
    layers rebuild every run.
  - `check-size` and `integration-test` each independently run `build_layers.sh` (~8 Docker
    builds each) instead of sharing one build artifact.
  - Fixed `sleep 45` for CloudWatch log ingestion instead of polling.
  - Each `serverless` CLI call is a cold Node.js process.
- **Fix:** Not yet applied. Planned in `lpimentel/ci-reduce-runtime` (TODO Fixes 2–5).
- **Improvement (pipeline):** See TODO.md fixes 2–5: honor `$ARCH`, add buildx GHA cache, share
  built layers as a workflow artifact, poll logs instead of `sleep 45`.

### 7. `check-size` rebuilds all 8 layers from scratch (2h17m on this PR)
- **What:** `check-size.yml` runs the same `build_layers.sh` (4 runtimes × 2 arches = 8 Docker
  builds) just to `stat` the resulting zip sizes. On PR #165 it took **2h17m34s**. (Slack #61–62;
  this session)
- **Fix:** Not yet applied. Planned in `lpimentel/ci-reduce-runtime` (TODO Fix 4).
- **Improvement (pipeline):** Build layers once in a dedicated job, upload as a workflow
  artifact, and have both `check-size` and `integration-test` download it. Collapses ~16 builds
  into ~4. Also bump Node 14.15 → 20 in `check-size.yml` (TODO Fix 6).

### 8. `check-size` is a required check → blocked merge
- **What:** `check-size` is a required status check, so PR #165 couldn't merge until the 2h17m
  job finished, even though all other checks (unit, lint, integration, mergegate) were green.
  (this session)
- **Fix:** Waited it out.
- **Improvement (pipeline):** Once Fix 4 (shared artifact) lands, `check-size` becomes a
  seconds-long `stat` job and stops being a merge bottleneck. Consider also making
  `DDCI Status` (which fails but is "Not required to merge") either green or removed to reduce
  noise.

### 9. Sign jobs failed — unsigned artifacts expired (1-hour window)
- **What:** The 8 `sign layer` jobs are **manual** and must be clicked within **1 hour** of the
  build jobs completing, because the template sets `expire_in: 1 hr` on unsigned layer zips. Too
  much time elapsed (operator stepped away), so 5 of 8 sign jobs failed with missing artifacts;
  the other 3 were still `manual` (not yet clicked). (Slack #64–70; this session)
- **Fix:** Re-ran all 8 `build layer` jobs (via GitLab API `jobs/:id/retry`), then immediately
  triggered all 8 `sign layer` jobs (retry the failed, play the manual). All 8 + the
  `signed layer bundle` succeeded. (this session)
- **Impact:** Lost the build artifacts; had to rebuild + re-sign. Rithika confirmed the 1-hour
  limit is "a little short and i can fix that" and will revisit across repos while on ER.
- **Improvement (pipeline):** Increase `expire_in` for unsigned artifacts (e.g., 1 day) so the
  manual sign step isn't a race. Better: make `sign layer` auto-run after build+test (it's not
  the actual public release — that's `publish layer prod`) and require manual approval only on
  the `publish` step. To be confirmed in the retro (Slack #71–74).

### 10. Sign jobs are manual — unclear why
- **What:** Operator asked why a human must click `sign layer` manually (Slack #71). Best guess
  (Rey): Jordan González implemented it; possibly because it "triggers the actual release".
  Rithika: "if that's not the case we can make it so that only the publish step needs human
  input." (Slack #71–74)
- **Fix:** None (proceeding manually).
- **Improvement (pipeline/docs):** In the retro, determine whether signing can be automatic
  (gated only on build+test success) with manual approval reserved for `publish layer prod`.
  If signing must stay manual, document *why* and the 1-hour deadline prominently in Confluence.

### 11. `me-south-1` prod publishes failed (region unavailable)
- **What:** 8 prod `publish layer` jobs failed, all in `me-south-1` (one per runtime/arch),
  with `Failed to connect to proxy URL: "http://127.0.0.1:15002"`. (Slack #82–84; this session)
- **Cause:** Rithika confirmed `me-south-1` is "the bombed dc" — the datacenter/region is no
  longer available.
- **Fix:** None needed — 264/272 prod publishes succeeded (all available regions). The 8
  me-south-1 failures are expected/unavoidable.
- **Improvement (pipeline):** Remove `me-south-1` from `.gitlab/datasources/regions.yaml` so
  it's no longer in the publish matrix (avoids 8 perpetual failures + red pipeline status on
  every release). The pipeline currently shows `status: failed` solely because of these.

### 12. GovCloud access lapsed
- **What:** Operator's GovCloud access/training has lapsed and can't run
  `scripts/publish_govcloud.sh`. (Slack #81, #87)
- **Fix:** Rey volunteered to do the GovCloud publish (us1-fed + us2-fed).
- **Improvement (docs):** Confluence should note that GovCloud publish requires (a) active
  SSO GovCloud access (`[profile sso-govcloud-us1-fed-engineering]`), (b) yearly training
  current, and (c) how to verify access before starting the release (Slack #90–98: "just try to
  log into govcloud... and try to access aws within that profile"). Surface this *before* the
  operator reaches step 6, so they can refresh access in parallel with earlier steps.

### 13. `DDCI Status` check fails but is "Not required to merge"
- **What:** The `DDCI Status` check consistently fails on PRs but is marked "Not required to
  merge." (this session)
- **Fix:** None — ignorable noise.
- **Improvement (pipeline):** Either fix the DDCI integration so it's green, or remove it as a
  reported check so it doesn't cry wolf on every PR.

---

## Cross-cutting themes

1. **First-time-operator gotchas are undocumented.** Several steps that "everyone knows" (RC
   region must be us-west-2; `LANGUAGES_SUBSET=ruby`; the 1-hour sign deadline; me-south-1 is
   dead; govcloud training must be current) are absent from Confluence. Each cost a pipeline
   re-run or a Slack round-trip.
2. **The pipeline is slow and wasteful.** Duplicate runs, dual-arch builds via qemu, no Docker
   cache, redundant layer builds across jobs, fixed sleeps. The `lpimentel/ci-reduce-runtime`
   branch + TODO.md capture the fixes; Fixes 1 & 2 alone roughly halve wall-time.
3. **Manual gates create race conditions.** The manual `sign layer` step combined with 1-hour
   artifact expiry is a footgun. Either auto-sign or lengthen the expiry.
4. **Dead regions pollute the matrix.** `me-south-1` in `regions.yaml` guarantees 8 failures
   and a red pipeline on every release.

---

## Concrete next steps

### Pipeline (tracked in `lpimentel/ci-reduce-runtime` / TODO.md)
- [ ] Fix 1 — Drop `push` trigger; add `concurrency` (trivial, ~50% time saved)
- [ ] Fix 2 — Honor `$ARCH` in `build_layers.sh` (small, ~40% per build)
- [ ] Fix 3 — buildx GHA cache; drop `--no-cache` for PRs (small)
- [ ] Fix 4 — Build layers once, share as artifact (medium; fixes #7 and #8)
- [ ] Fix 5 — Poll CloudWatch logs instead of `sleep 45` (small)
- [ ] Fix 6 — Node 14.15 → 20 in `check-size.yml` (trivial)
- [ ] Remove `me-south-1` from `.gitlab/datasources/regions.yaml` (issue #11)
- [ ] Increase unsigned-artifact `expire_in` and/or auto-run `sign layer` (issue #9, #10)
- [ ] Fix or remove `DDCI Status` check (issue #13)

### Docs (Confluence "Lambda Layer Ruby" page)
- [ ] RC section: state RC layers must publish to `us-west-2` (not `sa-east-1`) for e2e (issue #1)
- [ ] RC section: warn that omitting `LANGUAGES_SUBSET=ruby` tests all languages (issue #4)
- [ ] Note per-region layer versions are independent; `1` in a fresh region is expected (issue #2)
- [ ] Release section: prominently document the 1-hour sign deadline and that sign jobs are
      manual (and *why*) (issues #9, #10)
- [ ] Release section: note `me-south-1` is unavailable and its publish failures are expected
      (issue #11)
- [ ] GovCloud section: document access/training prerequisites and how to verify before
      starting the release (issue #12)

### Retro (suggested by Rey, Slack #72)
- [ ] Schedule a retro on the rb release process; use this doc as the agenda.
