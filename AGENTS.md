# AGENTS.md — Blackout

Standing order from Crisis: **run the strongest available thinking model, at max reasoning,
and do expert-level work.** Runs are launched from an iPhone and scored on one physical
device in airplane mode, so a guess that compiles is still a wasted TestFlight round trip.
Read this file before the first edit. `README.md` has the architecture; this has the loop.

## Where work lands

- Trunk is `cursor/blackout-bible-v3-64d0` (PR #4). Tip branches cut from it and PR back
  into it. `main` is the old vessel: do not merge into it, do not force-push anything.
- One tip per branch, named `cursor/<what-it-does>-<suffix>`.
- A PR body says what to tap on device and what proves it, and cites GHA run ids and commit
  SHAs the way `docs/TESTFLIGHT.md` does. Adjectives are not evidence.

## Do not ship by accident

`.github/workflows/testflight-internal.yml` uploads a real Internal build when a push to the
trunk carries a commit message starting with `tf:`, or on a `tf-*` tag. Nothing else fires
it, and a merge commit counts.

- Never write `tf:` unless Crisis asked for a build. Use `map:`, `fix(map):`, `docs(tf):`.
- Internal group only. No External, no App Review, no production.
- Tree `CURRENT_PROJECT_VERSION` stays **1** across all six configs. TestFlight injects the
  next CPV on the xcodebuild command line and never commits it.

## Run the guards before you push

Both are stdlib only, need no network and no Xcode, and finish in about fifteen seconds:

```bash
python3 tools/test_ci_opt.py     # CPV, signing, archive and workflow gates
bash tools/audit_offline.sh      # product invariants (chains tools/validate_v3.py)
```

`audit_offline.sh` runs `validate_v3.py`, which runs `test_graph_plan.py`,
`test_walkable_next_pack.py`, `test_tx_west_style.py` and `test_voice_nav.py`. That chain is
the executable form of the "Locked (do not regress)" list every tip PR restates by hand.
`.github/workflows/audit.yml` runs it on every push to the trunk and every PR into the trunk.

A new invariant ships as a new check in that chain, in the same commit as the behavior it
protects. If a guard is wrong, change the guard on purpose — do not route around it.

## Fail closed

The audit rejects `URLSession`, `WKWebView`, analytics SDKs, CloudKit, `MKMapView(`,
`tel://911` and coming-soon stub language anywhere under `Blackout/` or `Packages/`. Behind
those greps: bundled MapLibre tiles only, no Apple or Google base map, no account, no
backend. SOS logs before it arms and never auto-dials. Dark only. "Unknown" is a valid Vision
answer. When a capability is unavailable, the UI says so — it never spins.

## This box cannot build iOS

Cloud agents run Linux and there is no `xcodebuild` here. Swift is verified by the unsigned
macOS compile (`macos-14` + Xcode 16) and then by hand on the device.

- Keep Swift diffs small. One compile per push, no local type checker, no simulator.
- Confirm MapLibre API against `Vendor/MapLibre` rather than from memory: merge `c99b927`
  carried `convertPoint(_:toCoordinateFromView:)` and broke the build (34241309663, exit 65).
- Anything you cannot compile here, guard in python instead.

## Where to look

| File | What it holds |
|------|---------------|
| `README.md` | architecture, module rules, QA v1 musts |
| `docs/TESTFLIGHT.md` | every archive and upload failure with its fix, by GHA run id |
| `docs/DEVICE.md` | the cable run on Crisis's iPhone |
| `docs/SOLO_QA.md` | the device score sheet |
