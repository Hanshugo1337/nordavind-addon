# Loot Detection via CHAT_MSG_LOOT

**Date:** 2026-05-04  
**Status:** Approved

## Problem

`START_LOOT_ROLL` does not fire in modern WoW (Midnight, personal loot). Neither auto-need nor item detection works. Officers must manually add items via `/nordlc add` before starting a council session.

## Goal

After a boss is killed, automatically detect all dropped epic+ items and show a pre-session selection window. The officer reviews the items, removes any they don't want to council, then clicks "Start Council".

## Solution

Replace `START_LOOT_ROLL` as the primary detection event with `CHAT_MSG_LOOT`, gated on `BOSS_KILL`.

## Flow

1. `BOSS_KILL` fires → clear `droppedItems`, open an 8-second collection window
2. During the window, every `CHAT_MSG_LOOT` message is parsed for item links
3. Each item link runs through the existing `shouldTrackItem` filter (epic+, no toys/pets/consumables, tier token support, warbound exclusion)
4. Deduplicate by itemID — if multiple raiders receive the same item type, show it once
5. After 8 seconds, if any items were collected, call `NLC.UI.ShowLootDetected(droppedItems)`
6. Officer sees the existing loot panel — X to remove items, "Start Council" to proceed

## Changes

### LootDetection.lua (only file that changes)

- Register `CHAT_MSG_LOOT` alongside existing events
- On `BOSS_KILL`: clear state, schedule `C_Timer.After(8, showIfAny)`
- On `CHAT_MSG_LOOT`: if collection window is open and `NLC.isOfficer`, extract all item links from message text using pattern `|H(item:[^|]+)|h`, resolve each via `C_Item.GetItemInfoInstant`, run `shouldTrackItem` with retry, deduplicate by itemID, append to `droppedItems`
- `showIfAny`: if `#droppedItems > 0`, call `NLC.UI.ShowLootDetected(droppedItems)`
- Keep `START_LOOT_ROLL` handler for auto-need (may fire in some loot modes); remove its detection logic since CHAT_MSG_LOOT supersedes it
- Keep `ENCOUNTER_LOOT_RECEIVED` handler for looter-name tracking only (fills in `item.looter`)

### No changes to:
- `UI/CouncilFrame.lua` — loot panel already works
- `Council.lua` — session start flow unchanged
- Any other file

## Edge Cases

| Case | Handling |
|---|---|
| No items after 8s | Window not shown |
| Same itemID received by multiple players | Deduped — one row per itemID |
| Item not in cache yet | Existing retry logic (up to 5 × 0.5s) |
| Boss kill without activation | `NLC.active` guard at top of event handler |
| Non-officer | `NLC.isOfficer` guard — detection skipped |
| Loot from non-boss sources | Gated on 8s window after `BOSS_KILL` only |
