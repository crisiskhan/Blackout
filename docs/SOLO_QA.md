# SOLO QA — one phone

Setup: Airplane On, Bluetooth On, Wi-Fi off, cell off, ONE phone, no second device.

Score every row `[ ] PASS` / FAIL / N/A. Write the exact chrome string or behavior you saw.

## ARMING

- [ ] PASS / FAIL / N/A — INITIATE unlocks tabs (ARMING → MAP/COMMS/FIELD/EXPEDITION). Bundled logo is visible. No account prompt. No network/login gate.
- [ ] PASS / FAIL / N/A — No SOS disk on ARMING.
- [ ] PASS / FAIL / N/A — Pack list shows real pack names and sizes, **or** chrome `Packs missing from bundle — honest empty.`

## MAP

- [ ] PASS / FAIL / N/A — Active pack draws. Caption includes `MapLibre Metal offline` and `no MapKit engine`.
- [ ] PASS / FAIL / N/A — Search FTS returns pack POI names (type a known POI, submit).
- [ ] PASS / FAIL / N/A — MARK drops a `MARK <pack> <lat>, <lon>` line. Kill app and relaunch: the same mark is still listed.
- [ ] PASS / FAIL / N/A — LOCK-ON: if GPS or pack `graph.json` is usable, control shows `LOCKED` and no fake route is drawn. If both GPS and graph are missing, chrome `OFF GRAPH`. If motion/heading is allowed, a `BEARING <deg>°` line appears; if heading is denied, bearing stays empty (no invented course).
- [ ] PASS / FAIL / N/A — SPEAK speaks pack name + bearing, **or** chrome `SPEECH FAILED` (do not score a silent fake success).
- [ ] PASS / FAIL / N/A — Active pack name/size/state listed on MAP (same pack chosen on ARMING).
- [ ] PASS / FAIL / N/A — Browse MAP (lock-on off): no SOS disk.

## COMMS (solo, no peer)

- [ ] PASS / FAIL / N/A — Chrome starts `NET · NONE` (not `NET · MPC` / `NET · BLE` with nobody connected).
- [ ] PASS / FAIL / N/A — RALLY or DOWN: write stays local; chrome `NO PEERS · LOGGED`. No TX / sent claim.
- [ ] PASS / FAIL / N/A — HOLD PTT: chrome `NO PEERS · LOGGED`. Button stays `HOLD PTT` / `RELEASE PTT` — does not claim sent.
- [ ] PASS / FAIL / N/A — SOS is hold, not tap. A tap/release before hold ms does nothing. Disk is on COMMS only (plus lock-on MAP).
- [ ] PASS / FAIL / N/A — I AM OK is hidden while not joined (`NET · NONE`). No IAMOK bar.

## FIELD

- [ ] PASS / FAIL / N/A — Open a card. NEXT advances the step.
- [ ] PASS / FAIL / N/A — SPEAK speaks the card, **or** chrome `SPEECH FAILED`.
- [ ] PASS / FAIL / N/A — SEND TO PARTY with no peer: chrome `NO PEERS · LOGGED`. Write stays local.
- [ ] PASS / FAIL / N/A — CALL SOS is text only: `CALL SOS` plus `Offers iPhone Emergency SOS. Does not replace 911.` No SOS disk on FIELD.
- [ ] PASS / FAIL / N/A — Vision chrome is `NO VISION MODEL` (no percent, no hash-to-label ID). Honesty caption present.

## EXPEDITION

- [ ] PASS / FAIL / N/A — Hunger / Thirst / Pain / Water / Fatigue / Exposure sliders change CONDITION.
- [ ] PASS / FAIL / N/A — APPLY RED BAND with red-band vitals shows `RED` (self RED). CANCEL RED clears it. Solo send chrome `NO PEERS · LOGGED`.
- [ ] PASS / FAIL / N/A — `1 MIN TIMER SET` creates a 1-minute timer. After 1 minute chrome includes `OVERDUE` (not SOS). DONE removes it. Solo set/done chrome `NO PEERS · LOGGED`.
- [ ] PASS / FAIL / N/A — Roster QR is visible. JOIN LOCAL NET is not required to see the QR.
- [ ] PASS / FAIL / N/A — No SOS disk on EXPEDITION.

## INSTRUMENTS

- [ ] PASS / FAIL / N/A — MAP → INSTRUMENTS opens the instruments sheet (torch / compass / auction / ES·EN).

## WHAT WE CANNOT DO

- [ ] PASS / FAIL / N/A — First INITIATE after ARMING shows `WHAT WE CANNOT DO` once. I UNDERSTAND dismisses it. It does not return on later tab changes.

## Kill-and-relaunch

- [ ] PASS / FAIL / N/A — Party code typed on COMMS is still there after kill-and-relaunch.
- [ ] PASS / FAIL / N/A — MAP marks are still listed after kill-and-relaunch.
- [ ] PASS / FAIL / N/A — `WHAT WE CANNOT DO` stays dismissed after kill-and-relaunch.
- [ ] PASS / FAIL / N/A — Pack selected on ARMING is still the active pack on MAP after kill-and-relaunch.
