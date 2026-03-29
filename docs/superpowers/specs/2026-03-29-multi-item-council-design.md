# Multi-Item Council Redesign

## Problem

Current flow handles one item at a time with a 3-minute timer each. With 4-6 drops per boss and 20-30 raiders, that's 12-18 minutes of waiting per boss. Raiders get a popup, wait for timer, next popup, wait again.

## Solution

Show all boss drops in a single raider popup. Raiders respond to all items at once. Officers award items in a wizard flow that auto-advances.

## Raider-Side: Multi-Item Interest Popup

### Layout

```
+------------------------------------------+
|  Loot Council — Boss Name    [90s]   [X] |
|------------------------------------------|
|  [Void-Touched Chestplate]  ilvl 639     |
|  Equipped: [Old Chest] (626)  +13 ilvl   |
|  [ Upgrade ] [Catalyst] [Offspec] [Tmog] |
|  [note field - shown when Upgrade]       |
|------------------------------------------|
|  [Dreamrift Shoulders]  ilvl 639         |
|  Equipped: [Old Shoulders] (619)  +20    |
|  [ Upgrade ] [Catalyst] [Offspec] [Tmog] |
|------------------------------------------|
|  ... more items ...                      |
|------------------------------------------|
|         [ Send Responses ]               |
+------------------------------------------+
```

### Behavior

- One frame shows all items from the boss
- Each item row shows: item link, ilvl, equipped item comparison, ilvl diff
- Per item: four category buttons (Upgrade, Catalyst, Offspec, Tmog)
- Clicking a button highlights it as selected; clicking again deselects (= Pass)
- Upgrade shows an inline note field (optional, max 60 chars)
- Default state for all items is Pass (no selection)
- One shared 90-second timer at the top
- "Send Responses" button at the bottom sends all selections in one comm message
- Auto-close: frame closes and sends when timer expires (unselected items = Pass)
- Auto-close: frame closes and sends when all raid members with the addon have responded

### Auto-Close Tracking

- Officer tracks how many addon users are in the raid via a lightweight `HELLO` ping sent at session start
- Each raider's "Send Responses" triggers a `RESPOND` message to officer
- When respond count equals addon user count, officer closes collecting early
- Timer is the fallback — no response within 90s = Pass

## Officer-Side: Award Wizard

### Layout

```
+--------------------------------------------------+
|  Loot Council — Item 2 / 5        [<] [>]   [X] |
|  [Dreamrift Shoulders]  ilvl 639                 |
|--------------------------------------------------|
|  RANK  | NAVN       | SCORE | ILVL  | TIER | ...|
|--------------------------------------------------|
|  UPGRADE                                         |
|  RAIDER  Testwarrior  38.5   +13     3pc   Tildel|
|  RAIDER  Testshaman   36.2   +20     3pc   Tildel|
|  TRIAL   Testmage     25.8   +13     1pc   Tildel|
|--------------------------------------------------|
|  CATALYST                                        |
|  RAIDER  Testpaladin  32.0   +13     1pc   Tildel|
|--------------------------------------------------|
|         [Award Later]              [Lukk]        |
+--------------------------------------------------+
```

### Behavior

- Shows first item automatically when collecting phase ends
- Ranking list identical to current RankingFrame (score, ilvl diff, tier, warnings)
- Officer clicks "Tildel" on a candidate:
  - Item is awarded (comms, raid warning, history recorded)
  - Score updates live (lootThisWeek +1, baseScore -15)
  - Wizard auto-advances to next item
- Navigation: `<` and `>` arrow buttons to move between items manually
- Progress indicator: "Item 2 / 5" in title bar
- "Award Later" puts current item in pending queue, advances to next
- Last item: "Tildel" closes the wizard, or "Award Later" queues it
- If no candidates for an item (all passed), show "Ingen interesse" and a skip button

## Communication Protocol

### Messages

| Message | Direction | Payload | Description |
|---------|-----------|---------|-------------|
| `SESSION_START` | Officer -> Raid | `item1Link;item1Id;item1Ilvl;item1EquipLoc\|item2Link;...` | Starts multi-item session |
| `INTEREST` | Raider -> Officer | `itemId1:cat1:eqIlvl1:tier1:note1,itemId2:cat2:eqIlvl2:tier2:note2,...` | All responses in one message |
| `RESPOND` | Raider -> Officer | `count` (just a ping) | Signals raider has responded |
| `AWARD` | Officer -> Raid | `itemLink:playerName` | Award announcement (unchanged) |
| `SESSION_CLOSE` | Officer -> Raid | (empty) | Collecting phase ended |

### Backward Compatibility

Old single-item `COUNCIL_START` messages are no longer sent. Raiders without the updated addon won't see the multi-item popup. This is acceptable since all guild members update together.

## Changes Per File

### Council.lua
- `StartMultiSession(items)` replaces `StartSession()` for boss drops
- `StartSession()` kept for `/nordlc add` (single manual items)
- Track all sessions in `activeSessions` table (list) instead of single `activeSession`
- `BuildRanking()` unchanged (called per item during award phase)
- `Award()` modified to advance wizard index
- `respondCount` and `addonUserCount` tracking for auto-close

### Comms.lua
- New `SESSION_START` message type with multi-item payload
- New `RESPOND` message type for auto-close counting
- `INTEREST` updated to handle comma-separated multi-item responses
- Parse `HELLO` pings to count addon users

### UI/CouncilFrame.lua
- `ShowInterestPopup()` replaced by `ShowMultiItemPopup(items, timer)`
- Scrollable frame with item rows
- Per-item category buttons with highlight state
- Single "Send Responses" button
- Timer display at top

### UI/RankingFrame.lua
- `ShowRanking()` updated to accept session list + current index
- Arrow navigation buttons added
- Progress indicator "Item N / M"
- Auto-advance on award
- "Skip" button for items with no interest

### LootDetection.lua
- No changes needed — already collects all items into `droppedItems`

### Core.lua
- `StartSession` in loot panel's "Start Council" button calls `StartMultiSession(items)` instead
- Test commands updated for multi-item flow
- Timer config default changed from 30 to 90

### Scoring.lua
- No changes needed

### Utils.lua
- No changes needed

## Timer

- 90 seconds for the entire batch, not per item
- Countdown shown at top of raider popup
- Color-coded: gold > 30s, orange 10-30s, red < 10s
- Auto-close triggers when: timer expires OR all addon users have responded
- On auto-close: any unselected items are treated as Pass
