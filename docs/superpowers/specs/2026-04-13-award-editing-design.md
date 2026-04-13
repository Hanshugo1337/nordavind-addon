# Award Editing — Design Spec
Date: 2026-04-13

## Overview

Officers and the raid leader need to correct awards after they've been given — wrong recipient, wrong category. This adds an edit flow to both the TradeFrame (pending items) and a new History Frame (all awards).

## Components

### 1. History Frame (`/nordlc history`)

- New frame listing all entries in `NLC.db.lootHistory`
- Scrollable list, newest first
- Each row shows: item link, awarded to, category, boss, date
- Two buttons per row: **Endre** and **Slett**
- Accessible via `/nordlc history` slash command
- Only visible to officers/leader (`NLC.isOfficer`)

### 2. Edit Button in TradeFrame

- Add **Endre**-knapp next to the existing Trade-button for each pending item
- Opens the shared edit popup

### 3. Edit Popup (shared)

- Text input for new recipient (player name)
- Dropdown for category: Upgrade / Catalyst / Offspec / Tmog
- **Lagre** and **Avbryt** buttons
- Pre-filled with current values when opened

### 4. Save Logic

When saving an edit, update all three stores:
- `NLC.db.lootHistory` — always updated (match by timestamp + itemId)
- `NLC.db.pendingExport` — updated if entry still present
- `NLC.db.pendingTrades` — updated if item still pending trade

### 5. Delete Logic

Removes entry from all three stores. No confirmation dialog (keep it simple).

## Data Flow

```
User clicks Endre
  → Edit popup opens (pre-filled)
  → User changes recipient and/or category
  → User clicks Lagre
    → Find matching entry in lootHistory by timestamp + itemId
    → Update awardedTo + category
    → Find matching entry in pendingExport (same fields) → update
    → Find matching entry in pendingTrades (same itemId + old awardedTo) → update
    → Close popup, refresh frame
```

## Architecture Notes

- Edit popup is a single reusable frame, shared between TradeFrame and HistoryFrame
- HistoryFrame is a new file: `UI/HistoryFrame.lua`
- Edit popup lives in `UI/HistoryFrame.lua` (used by both frames)
- TradeFrame calls `NLC.UI.ShowEditPopup(entry, onSave)` callback pattern

## Role Priority in Ranking

DPS players always rank above Tanks and Healers, regardless of score. Score is only used to rank within the same role group.

**Implementation:** Two-level sort in `Council.BuildRanking()`:
1. Primary sort: role tier — `dps` = 1, `tank`/`healer` = 2
2. Secondary sort: score (descending) within same role tier

Role tier is shown as a label in RankingFrame (e.g. "DPS" / "Tank" / "Healer"). The `role` field is already available from importdata.

## Loot This Week — Fix og Ukentlig Reset

### Problem
`lootThisWeek` inkrementeres lokalt i session (Council.lua) men persisteres ikke — etter `/reload` starter telleren på null igjen fra import-data.

### Løsning
Spor ukentlig loot i `NLC.db` (SavedVariables) separat fra importdata:

```
NLC.db.weeklyLoot = {
  resetTimestamp = <unix timestamp for siste onsdag>,
  counts = { ["Playername"] = 2, ... }
}
```

**Ved award:** inkrementer `NLC.db.weeklyLoot.counts[playerName]`

**Ved scoring:** bruk `NLC.db.weeklyLoot.counts[playerName]` i stedet for `imported.lootThisWeek`

**Reset hver onsdag (WoW weekly reset):**
- Sjekk ved `PLAYER_ENTERING_WORLD` om nåværende tid > neste onsdag 09:00 UTC siden forrige reset
- Hvis ja: sett `counts = {}` og oppdater `resetTimestamp`
- Onsdag 09:00 UTC = WoW EU weekly reset

**Companion app:** `lootThisWeek` i importdata brukes fortsatt som "baseline" fra forrige eksport, men addon-telleren (`weeklyLoot.counts`) tar presedens under en aktiv uke.

## Wishlist Filter (WoWAudit)

Spillere som ikke har wishlistet itemet på WoWAudit skal **ikke** vises i rangeringen for "upgrade"-kategorien.

**Dataflyt:**
1. WoWAudit `/v1/characters` returnerer `wishlist: [{ id, name, slot }, ...]` per karakter
2. Web-eksport (`/api/loot/addon-export`) inkluderer `wishlist: [itemId, ...]` per spiller
3. Addon filtrerer i `BuildRanking`: upgrade-kandidater uten itemets ID i wishlisten ekskluderes
4. Catalyst/offspec/tmog er unntatt — wishlist gjelder bare upgrade

**Merk:** WoWAudit API-format for wishlist må verifiseres mot faktisk API-respons før implementasjon.

## Equipped Item i Ranking

Vis hva spilleren har utstyrt i det aktuelle slottet direkte i ranking-raden.

**Implementasjon (in-game API):**
- Bruk `GetInventoryItemLink(unit, slotId)` for raid-medlemmer
- `equipLoc → slotId`-mapping (f.eks. `INVTYPE_HEAD = 1`, `INVTYPE_CHEST = 5`)
- Hent item-link for hvert kandidat-navn via `GetInventoryItemLink`
- Vis som tooltip eller liten tekst under spillernavnet i RankingFrame

**Fallback:** Bruk eksisterende `equippedIlvl`-tall hvis item-link ikke er tilgjengelig (spiller ikke i raid).

## Out of Scope

- Re-sending AWARD comms message to raid members after edit (edit is local only)
- Pagination for history (scrollable list is sufficient)
- Undo functionality
