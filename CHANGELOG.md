# NordavindLC Changelog

## 1.9.0 (2026-08-18)

Sesong 2-releasen. Alt siden 1.8.0 (16. juni) — sesong 2-reglene, officer-avstemming, omskrevet loot-deteksjon og roster-import.

### Sesong 2-reglene håndheves nå i addonet

- **Ny sorteringsrekkefølge:** kategori → rank → score → færrest items denne sesongen → seedet terning. `roleTier` er fjernet — den lot en DPS med lav score slå en tank med høy, fordi rollen allerede ligger som +5 i baseScore fra nettsida.
- **Rank er et hardt skille** — en trial rangeres aldri over en raider. Ukjent rank havner sist, aldri først.
- **Sorteringsrang skilt fra visningsrang,** så backups kan legges bak trials ved sesongstart uten at addonet viser feil rang.
- **Uavgjort avgjøres likt som på nordavind.cc.** Terningen er FNV-1a over UTF-8-bytes, samme hash som nettsida, så begge verktøy gir samme svar på samme data. Før dette avgjorde `table.sort` vilkårlig.
- **Ukesstraffen er 10 poeng,** offspec er fritatt fra ukestelleren, og omfordeling av et award flytter straffen med itemet.
- **Ukesgrensa spørres av spillet** (`C_DateAndTime.GetSecondsUntilWeeklyReset`) i stedet for å regnes lokalt. Resetten er onsdag 07:00 lokal servertid — den gamle utregningen bommet.
- **Oppmøtevarselet flyttet fra 80 til 90,** som er kravet i sesong 2.

### Officer-avstemming

- Rådgivende avstemming under councilet: lederen deler ut, men er det stemt over itemet **kreves begrunnelse**.
- Stemmetall og begrunnelse følger med til `LootDrop.note` og vises i loot-historikken på nordavind.cc.
- Testbart alene med `/nordlc test` + `/nordlc testvote`.

### Loot-deteksjon og fordeling

- **Distribuert innsamling** — bag-scan etter boss-kill i stedet for å lese loot-vinduet, som ble upålitelig med Group Loot.
- **Loot Detected-panel** med ikoner, hvem som lootet, live responsteller, nedtellingsmerke og hastesortering.
- **Roll-off mellom kandidater** via `RandomRoll` med fangst fra system-chatten. 15-sekundersvinduet kan avbrytes.
- **Kunngjøring i raid warning** ved tildeling, endring og DE/bank/fri.
- **Egen dropdown** erstatter de ødelagte `MenuUtil`-menyene.

### Auto-rull

- **Raidlederen ruller ikke lenger Need på blindt.** Need er bare tilbudt på det egen spec kan bruke — en plate-leder kan ikke Neede en leather-del. Kallet ble da forkastet i stillhet, og siden alle andre auto-passer, endte itemet uten et eneste gyldig rull. Nå sjekkes `canNeed` først, med Transmog og deretter Greed som fallback. Disenchant velges aldri automatisk; det er councilets avgjørelse.
- **Auto-rull utsettes 0,05 sekund.** Et kall som lander mens et annet addon bygger om rull-framen forsvinner uten feilmelding.

### Roster-import

- **`/nordroster`** fanger hele guild-rosteret med public notes, officer notes, rang, klasse og realm, og sender det via companion til nordavind.cc for godkjenning.
- Ingen hardkodet realm noe sted — guilden er cross-realm.

### Kompatibilitet

- **Interface oppdatert til 120100, 120005, 120007** (Midnight 12.1.0). 1.8.0 sto på 120001/120005 og ble derfor merket «Out of date», så addonet ikke lastet uten manuell avhuking.
- **Comms leser restriksjonen fra event-payloaden** i stedet for å polle. Meldinger sendt i `Activating`-vinduet — som treffer encounter-start — forsvant stille før.
- **`ROLL_CALL_ACK` bærer addon-versjonen,** så offiseren varsles ved council-start om noen kjører en annen versjon.

### Kjent begrensning

- **Sim-poeng mangler fortsatt i addonet.** Nettsida legger inntil 8 poeng for sim-oppgradering; addonet gjør ikke. Rangeringen kan derfor avvike fra nordavind.cc. Blokkert på at sim-tallene for sesong 2 ikke finnes ennå.

## 1.7.5 (2026-04-29)

### Bug Fixes

- **Score breakdown tooltip fixed** — score breakdown in the ranking tooltip always showed 0.0 due to a key mismatch (`points` vs `value`) between Scoring.lua and RankingFrame.lua
- **Wizard no longer forces open for raiders** — non-officer raiders no longer see the ranking/wizard window when the collection phase ends; only the awarding officer sees it
- **Timer minimum enforced at 90s** — config timer is now enforced to at least 90 seconds on load, fixing cases where a stale SavedVariables value caused the popup to close too early
- **`/nordlc timer <sek>` command added** — officers can now change the response timer in-game

## 1.7.4 (2026-04-29)

### Bug Fixes

- **Tmog logic overhauled** — tmog now defaults to hidden and is only shown for armor of the wrong type in non-tier slots. Previously tmog defaulted to visible and was only explicitly hidden for tier slots, causing it to incorrectly appear alongside Upgrade/Offspec on items you can actually use.

## 1.7.3 (2026-04-15)

### New Features

- **Auto-need for raid leader** — når loot dropper auto-needer raid leaderen på alt automatisk; WoW blokkerer warbound items selv. Alle andre auto-passer som før.

## 1.7.2 (2026-04-15)

### Bug Fixes

- **Tmog teller ikke som loot denne uken** — tmog-awards øker ikke lenger den ukentlige loot-telleren
- **Ukentlig teller resettes riktig på onsdager** — etter onsdag-reset falt telleren tilbake til gammel importdata; nå brukes alltid in-game tellingen når en reset er registrert

## 1.7.1 (2026-04-15)

### Bug Fixes

- **Tmog hidden for tier pieces** — tier slot items (head, shoulder, chest, hands, legs) no longer show the Tmog button; only Upgrade, Catalyst, and Offspec are available for tier
- **Correct buttons for uncached items** — when an item's data hasn't loaded in a raider's client yet (can happen when SESSION_START arrives before WoW caches the item), tier slots now correctly show Catalyst and hide Tmog instead of defaulting to Upgrade + Tmog

## 1.7.0 (2026-04-14)

### New Features

**Award Editing**
- Officers can now edit awards after the fact — change recipient and/or category
- Endre button appears on every row in both the history view and the pending trades list
- Edits sync automatically to the database via the companion app

**Award History** (`/nordlc history`)
- New scrollable history browser showing all past awards, newest first
- Each row shows item, recipient, category, and date
- Endre button to correct mistakes, Slett button to remove an entry

**Reopen Council Window** (`/nordlc council`)
- If you accidentally close the ranking window mid-council, type `/nordlc council` to bring it back
- Left-clicking the minimap icon also reopens the active council window

**DPS Priority**
- DPS players now rank above tanks and healers within the same category and score tier
- A small colored role label (DPS / Tank / Healer) is shown below each player's name in the ranking frame

**Equipped Item Tooltip**
- Hover over the ilvl column in the ranking frame to see the full item tooltip of what that player currently has equipped in that slot
- Shows the actual item link, not just the ilvl number

**Wishlist Filter (WoWAudit integration)**
- Players without an item on their WoWAudit wishlist will not see the Upgrade button for that item
- Officers' ranking view also filters out upgrade candidates who don't have the item wishlisted
- Requires companion app sync to pull the latest wishlists from WoWAudit

**Weekly Loot Tracking**
- Weekly loot counts now persist across game sessions (previously reset on logout)
- Automatically resets every Wednesday at 09:00 UTC (EU reset time)

### Bug Fixes

- Fixed tier items (Head, Shoulders, Chest, Hands, Legs) only showing Tmog instead of Upgrade/Catalyst/Offspec
- Fixed raid leader auto-passing on all loot — leader now correctly holds loot for trading
- Fixed loot detection window not appearing after boss kills
- Fixed role label appearing to the left of the player name instead of below it
- Addon now loads correctly on WoW 12.0.5 (interface version updated)

### Companion App

- Picks up `pendingEdits` from SavedVariables and syncs award changes to the database
- Wishlists are included in the scoring export from the web server

---

## 1.6.0

- Award confirmation dialog before finalizing
- Tmog rolls (random 0–100 per candidate)
- Auto-pass fix for non-leader players
- Warbound item filter (warbound items excluded from council)
- Tier set detection (highlights when a player is 1 or 3 pieces away from a bonus)
- Companion app v2 with Express web dashboard and auto-sync
