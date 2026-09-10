# SOLO QA — one phone

Setup: Airplane On, Bluetooth On, Wi-Fi off, cell off, ONE phone, no second device.

Score every row `[ ] PASS` / FAIL / N/A. Write the exact chrome string or behavior you saw.

## BOOT

- [ ] PASS / FAIL / N/A — Cold launch is the logo on void, not an ARMING menu. No pack list, no left-hand toggle, no night-red on that screen. Bundled logo is visible. No account prompt. No network/login gate.
- [ ] PASS / FAIL / N/A — Status line moves through the shipped packs, then `READY`. ACTIVATE is dead until then, then live. Tap ACTIVATE → MAP/COMMS/FIELD/EXPEDITION.
- [ ] PASS / FAIL / N/A — No SOS disk on the boot screen. If packs are missing, the status line is `Packs missing from bundle — honest empty.`

## MAP STILL — tip 60 score bar (five only)

Score the MAP still. Do not score Vision, Field cards, Watch, or new packs.

- [ ] PASS / FAIL — full-height canvas
- [ ] PASS / FAIL — pack outline+puck
- [ ] PASS / FAIL — single MARK
- [ ] PASS / FAIL — no CALL SOS on browse MAP
- [ ] PASS / FAIL — no solid-red slab

## MAP

- [ ] PASS / FAIL / N/A — Active pack draws full-height under the HUD (search + INSTRUMENTS + LOCK-ON overlay the canvas; the tab strip overlays the bottom). Pinch-out shows pack outline + YOU puck, no solid-red slab. OSM credit `© OpenStreetMap contributors` is visible. No `style.json` / `MapLibre Metal offline` / `no MapKit engine` debug chrome on the canvas.
- [ ] PASS / FAIL / N/A — MAP thumb dock: MARK / WALK / DRIVE / SPEAK are equal-width 44pt cells (never disabled). INSTRUMENTS and LOCK-ON sit under search as whole words (they wrap; they never become `INST` or `INSTRUME…`). RULER / USNG / MAG/TRUE live in INSTRUMENTS, not on the canvas. Other MapTool leftovers are not on MAP.
- [ ] PASS / FAIL / N/A — Search FTS returns pack POI names (type a known POI, submit). Hits cap at five — no scroll on MAP.
- [ ] PASS / FAIL / N/A — MARK drops one `MARK <pack> <lat>, <lon>` line per coordinate (no duplicate rows from one tap). If GPS is outside the open pack, chrome is `OFF PACK` and the mark is labeled `OFF PACK` (not the pack name). Kill app and relaunch: the same mark is still listed.
- [ ] PASS / FAIL / N/A — LOCK-ON: if GPS or pack `graph.json` is usable, control shows `LOCKED` and no fake route is drawn. If both GPS and graph are missing, chrome `OFF GRAPH`. `BEARING <deg>°` only appears when there is somewhere to walk (a destination, a drawn route, or LOCK-ON). Idle heading with no dest is quiet. If heading is denied, bearing stays empty (no invented course).
- [ ] PASS / FAIL / N/A — WALK / DRIVE: tap the map, a search hit, or a MARK row to set `DEST`. Then WALK or DRIVE. If the TX WEST graph has a path, a cyan route line follows the streets (not bearing-only chrome). If the graph is missing/empty or there is no path, chrome `OFF GRAPH` and no fake street-following line.
- [ ] PASS / FAIL / N/A — SPEAK chip stays visible. After DEST + WALK, SPEAK **speaks** the whole turn-by-turn out loud (Walk / Turn / Arrive) while the cyan route line stays on the map. Score the voice and the line, not text on the canvas. Volume up, silent switch off.
- [ ] PASS / FAIL / N/A — SPEAK paints **no** walk script on the field. The only Speak chrome is one short line: `SPEAK · 3 TURNS · 300 M` (or `SPEAK · DEST 1240 M` / `SPEAK · SET DEST` / `SPEAK · OFF GRAPH` / `SPEECH FAILED`). Any orange paragraph, `Walk … Turn … Arrive` text, or multi-line HUD over the canvas is a FAIL.
- [ ] PASS / FAIL / N/A — MAP HUD reads whole words: search field, `INSTRUMENTS`, `LOCK-ON`/`LOCKED`, dock `MARK` `WALK` `DRIVE` `SPEAK`. No `INST`, no `INSTRUME…`, no `…` on those controls. INSTRUMENTS opens the instruments sheet. SPEAK is on the dock, not the header.
- [ ] PASS / FAIL / N/A — Field chrome is at most three short lines and each one fits on its line. Status (`OFF GRAPH` / `TRUE NORTH` / `RULER …`) reads once — never `OFF GRAPH` twice, never a bare `TRUE`. With a dest or LOCK-ON, bearing is `BEARING 45°` (the pin is on the canvas — no `DEST 31.7619, -106.4850`). With a good pack and no DEST picked yet, there is no `OFF GRAPH` and no `BEARING`, and the Speak line is gone until you tap SPEAK again.
- [ ] PASS / FAIL / N/A — Pinch to walking zoom (a block or two across): silver street names are drawn on the streets with a black halo and are legible at arm's length. If no name draws at any zoom, the glyph template failed — report it.
- [ ] PASS / FAIL / N/A — Active pack name/size/state listed on MAP (TX WEST first-open, or the pack last chosen in INSTRUMENTS).
- [ ] PASS / FAIL / N/A — Browse MAP (lock-on off): no SOS disk.

## COMMS (solo, no peer)

- [ ] PASS / FAIL / N/A — Chrome starts `NET · NONE` (not `NET · MPC` / `NET · BLE` with nobody connected).
- [ ] PASS / FAIL / N/A — RALLY or DOWN: write stays local; chrome `NO PEERS · LOGGED`. No TX / sent claim.
- [ ] PASS / FAIL / N/A — HOLD PTT: chrome `NO PEERS · LOGGED`. Button stays `HOLD PTT` / `RELEASE PTT` — does not claim sent.
- [ ] PASS / FAIL / N/A — SOS is hold, not tap. A tap/release before hold ms does nothing. Disk is on COMMS only (64pt, pulsing while held, visible SOS). Browse MAP (lock-on on or off) has no SOS FAB. After hold: mesh chip + RED + POS (`SOS · MESH` plate), not a caption. I AM OK clears it.
- [ ] PASS / FAIL / N/A — I AM OK is hidden while not in SOS/RED and while not joined (`NET · NONE`). No always-on IAMOK bar.
- [ ] PASS / FAIL / N/A — COMMS / FIELD / EXPEDITION are glass HUD pages over the still-mounted map (not form dumps). Tab strip reads EXPEDITION, not EXPED. No `Whisper <10 m` dump on COMMS.
- [ ] PASS / FAIL / N/A — Hold a water/ground feature → FIELD. The hold card must not crash. Field opens the matching procedure. Returning to MAP still has the canvas (MapLibre was not torn down).

## FIELD

- [ ] PASS / FAIL / N/A — Open a card. NEXT advances the step.
- [ ] PASS / FAIL / N/A — SPEAK speaks the card, **or** chrome `SPEECH FAILED`.
- [ ] PASS / FAIL / N/A — SEND TO PARTY with no peer: chrome `NO PEERS · LOGGED`. Write stays local.
- [ ] PASS / FAIL / N/A — CALL SOS is text only: `CALL SOS` plus `Offers iPhone Emergency SOS. Does not replace 911.` No SOS disk on FIELD.
- [ ] PASS / FAIL / N/A — Vision chrome is `NO VISION MODEL` (no percent, no hash-to-label ID). No CoreML lecture under it.

## EXPEDITION

- [ ] PASS / FAIL / N/A — Hunger / Thirst / Pain / Water / Fatigue / Exposure sliders change CONDITION.
- [ ] PASS / FAIL / N/A — APPLY RED BAND with red-band vitals shows `RED` (self RED). CANCEL RED clears it. Solo send chrome `NO PEERS · LOGGED`.
- [ ] PASS / FAIL / N/A — `1 MIN TIMER SET` creates a 1-minute timer. After 1 minute chrome includes `OVERDUE` (not SOS). DONE is one row per timer id (`1min ALL DONE` once). JOIN NAV is one `nav Nav` row. Solo set/done chrome `NO PEERS · LOGGED`.
- [ ] PASS / FAIL / N/A — Roster QR is visible. JOIN LOCAL NET is not required to see the QR.
- [ ] PASS / FAIL / N/A — No SOS disk on EXPEDITION.

## INSTRUMENTS

- [ ] PASS / FAIL / N/A — MAP → INSTRUMENTS opens the instruments sheet. MAP section is RULER / USNG / MAG/TRUE (44pt). Torch / compass / auction / ES·EN still there. Tapping a MAP instrument dismisses the sheet so the canvas status is visible.
- [ ] PASS / FAIL / N/A — INSTRUMENTS → PACKS switches TX WEST / NM / TX EAST. Streets and a local WALK/DRIVE graph should be present at walking zoom with © OpenStreetMap. Left-hand and night-red live here, not on boot.

## WHAT WE CANNOT DO

- [ ] PASS / FAIL / N/A — First ACTIVATE shows `WHAT WE CANNOT DO` once. I UNDERSTAND dismisses it. It does not return on later tab changes.

## Kill-and-relaunch

- [ ] PASS / FAIL / N/A — Party code typed on COMMS is still there after kill-and-relaunch.
- [ ] PASS / FAIL / N/A — MAP marks are still listed after kill-and-relaunch.
- [ ] PASS / FAIL / N/A — `WHAT WE CANNOT DO` stays dismissed after kill-and-relaunch.
- [ ] PASS / FAIL / N/A — Pack selected in INSTRUMENTS → PACKS is still the active pack on MAP after kill-and-relaunch.
