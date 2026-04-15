# NordavindLC Changelog

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
