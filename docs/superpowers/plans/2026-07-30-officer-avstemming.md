# Officer-avstemming — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gi lederen en knapp i wizarden som ber officers stemme over hvem som får et item, med begrunnelsen lagret helt ned i databasen.

**Architecture:** Speiler roll-off-mekanikken i `Council.lua` — kringkast over `NLC.Comms`, samle svar, vis resultat hos lederen. Avstemmingen er rådgivende: lederen deler ut som før, men når en avstemming er aktiv kreves en begrunnelse, og den følger itemet gjennom `pendingExport` → companion → API → `LootDrop.note`.

**Tech Stack:** Lua (WoW 12.0, AceComm/AceSerializer), Node.js (companion, `node --test`), Next.js + Prisma (web), PostgreSQL.

## Global Constraints

- Migrasjoner hører **kun** hjemme i `nordavind-bot/prisma/migrations/`. Botten auto-migrerer ved oppstart. Bruk alltid `ADD COLUMN IF NOT EXISTS`.
- Commits i `nordavind-bot` skal **ALDRI** ha `Co-Authored-By`-linje (repoets egen CLAUDE.md). Commits i `nordavind-web` og `nordavind-addon` skal ha `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Ingenting pushes** uten eksplisitt klarsignal.
- Grener: `sesong2-loot-kategori` i addon, `sesong2-oppmote` i web og bot.
- All brukervendt tekst på norsk.
- `nordavind-addon` har løse `.zip`-er og en gammel `.exe` i arbeidstreet — stage **aldri** med `git add -A`.
- Ingen Lua-testrunner og ingen `luac`/`luacheck` i miljøet. Lua-oppgaver verifiseres med `/nordlc test` (Task 6) og nøye gjennomlesing. JS-oppgaver får ekte tester.
- Addonet må kopieres til `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\NordavindLC` for å testes — mappa er en **kopi**, ikke en junction.

---

### Task 1: `note` gjennom database, API og companion

Bygger fundamentet nedenfra, slik at resten kan bygges mot et endepunkt som beviselig virker. Ingen Lua i denne oppgaven.

**Files:**
- Modify: `nordavind-bot/prisma/schema.prisma`
- Create: `nordavind-bot/prisma/migrations/20260730120000_loot_drop_note/migration.sql`
- Modify: `nordavind-web/prisma/schema.prisma`
- Modify: `nordavind-web/app/api/loot/addon/route.ts`
- Modify: `nordavind-addon/companion/lib/api-client.js`
- Test: `nordavind-addon/companion/test/api-client.test.js`

**Interfaces:**
- Produces: `LootDrop.note String?` i begge schemaer. `POST /api/loot/addon` godtar `note` i body. `ApiClient.awardLoot({ item, awardedTo, awardedBy, boss, timestamp, category, note })`.

- [ ] **Step 1: Legg feltet i begge schemaer**

I `nordavind-bot/prisma/schema.prisma` og `nordavind-web/prisma/schema.prisma`, i `model LootDrop`, rett under `category`:

```prisma
  category String? // upgrade | catalyst | offspec | tmog
  note     String? // satt ved officer-avstemming: stemmetall + begrunnelse
```

- [ ] **Step 2: Skriv migrasjonen**

Opprett `nordavind-bot/prisma/migrations/20260730120000_loot_drop_note/migration.sql`:

```sql
-- IF NOT EXISTS fordi web-repoet har samme felt i sitt schema; har noen kjørt
-- `prisma db push` derfra, feiler et rent ADD COLUMN med "column already exists",
-- migrasjonen markeres failed og botten crash-looper ved oppstart.
ALTER TABLE "loot_drops" ADD COLUMN IF NOT EXISTS "note" TEXT;
```

- [ ] **Step 3: Skriv den feilende testen for companion**

Opprett `nordavind-addon/companion/test/api-client.test.js`:

```js
"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { ApiClient } = require("../lib/api-client");

function fakeFetch(captured) {
  return async (url, opts) => {
    captured.url = url;
    captured.body = JSON.parse(opts.body);
    return { ok: true, json: async () => ({ ok: true, lootDropId: 1 }) };
  };
}

test("awardLoot sender note videre til API-et", async () => {
  const captured = {};
  const orig = global.fetch;
  global.fetch = fakeFetch(captured);
  try {
    const api = new ApiClient("https://nordavind.cc", "key");
    await api.awardLoot({
      item: "Voidforged Greaves",
      awardedTo: "Reevo",
      awardedBy: "Fisk",
      boss: "Kaelthar",
      timestamp: 1755500000,
      category: "upgrade",
      note: "officer-avstemming 3-2-1 — oppmøte feilregistrert",
    });
  } finally {
    global.fetch = orig;
  }
  assert.equal(captured.body.note, "officer-avstemming 3-2-1 — oppmøte feilregistrert");
  assert.equal(captured.body.category, "upgrade");
});

test("awardLoot uten note sender undefined, ikke tom streng", async () => {
  const captured = {};
  const orig = global.fetch;
  global.fetch = fakeFetch(captured);
  try {
    const api = new ApiClient("https://nordavind.cc", "key");
    await api.awardLoot({
      item: "Voidforged Greaves",
      awardedTo: "Reevo",
      awardedBy: "Fisk",
      boss: "Kaelthar",
      timestamp: 1755500000,
      category: "upgrade",
    });
  } finally {
    global.fetch = orig;
  }
  assert.equal("note" in captured.body, false);
});

test("editAward sender fortsatt newCategory", async () => {
  const captured = {};
  const orig = global.fetch;
  global.fetch = fakeFetch(captured);
  try {
    const api = new ApiClient("https://nordavind.cc", "key");
    await api.editAward({
      originalTimestamp: 1755500000,
      item: "Voidforged Greaves",
      newAwardedTo: "Braxina",
      newCategory: "offspec",
    });
  } finally {
    global.fetch = orig;
  }
  assert.equal(captured.body.newCategory, "offspec");
});
```

- [ ] **Step 4: Kjør testen og se at den feiler**

```bash
cd nordavind-addon/companion && node --test test/api-client.test.js
```

Forventet: FAIL på første test — `captured.body.note` er `undefined` fordi `awardLoot` ikke destrukturerer `note`.

- [ ] **Step 5: Send `note` fra companion**

I `nordavind-addon/companion/lib/api-client.js`, endre `awardLoot`:

```js
  async awardLoot({ item, awardedTo, awardedBy, boss, timestamp, category, note }) {
    const res = await fetch(`${this.baseUrl}/api/loot/addon`, {
      method: "POST",
      headers: { "x-api-key": this.apiKey, "Content-Type": "application/json", "Host": "nordavind.cc" },
      body: JSON.stringify({ item, awardedTo, awardedBy, boss, timestamp, category, note }),
      signal: AbortSignal.timeout(10000),
    });
```

`JSON.stringify` utelater nøkler med verdi `undefined`, så test 2 passerer uten ekstra logikk.

- [ ] **Step 6: Kjør testene og se at de passerer**

```bash
cd nordavind-addon/companion && node --test
```

Forventet: alle grønne (de 7 eksisterende + 3 nye).

- [ ] **Step 7: Ta imot `note` i API-et**

I `nordavind-web/app/api/loot/addon/route.ts`, utvid body-typen i `POST`:

```ts
  let body: {
    item?: string;
    awardedTo?: string;
    awardedBy?: string;
    boss?: string;
    timestamp?: number;
    category?: string;
    note?: string;
  };
```

Endre destrukturering og `create`:

```ts
  const { item, awardedTo, awardedBy, boss, timestamp, category, note } = body;
```

```ts
  const lootDrop = await prisma.lootDrop.create({
    data: {
      item,
      givenTo: recipientUser.discordId,
      givenBy,
      raidId: currentRaid?.id ?? null,
      boss: boss ?? null,
      category: category ?? "upgrade",
      note: note ?? null,
      createdAt: timestamp ? new Date(timestamp * 1000) : undefined,
    },
  });
```

- [ ] **Step 8: Regenerer Prisma-klienten og typecheck**

```bash
cd nordavind-web && npx prisma generate && npx tsc --noEmit
```

Forventet: begge exit 0.

- [ ] **Step 9: Commit — tre repoer, ulike regler**

```bash
cd nordavind-bot && git add prisma/schema.prisma prisma/migrations/20260730120000_loot_drop_note/migration.sql
git commit -m "feat(db): note-felt paa LootDrop for officer-avstemming

Baerer stemmetall og begrunnelse naar et item deles ut utenom lista,
slik at unntaket staar i loot-historikken og ikke bare i en chat-logg."
```

```bash
cd ../nordavind-web && git add prisma/schema.prisma app/api/loot/addon/route.ts
git commit -m "feat(loot): API-et tar imot note paa award

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

```bash
cd ../nordavind-addon && git add companion/lib/api-client.js companion/test/api-client.test.js
git commit -m "feat(companion): send note videre til nordavind.cc

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `RecordAward` bærer `note`

**Files:**
- Modify: `nordavind-addon/NordavindLC/Core.lua:209-228`

**Interfaces:**
- Consumes: ingenting fra tidligere tasks.
- Produces: `NLC.RecordAward(item, awardedTo, awardedBy, boss, category, itemId, exportable, note)` — `note` er valgfri streng, havner på `lootHistory`- og `pendingExport`-oppføringene.

- [ ] **Step 1: Legg `note` på signaturen og oppføringen**

I `NordavindLC/Core.lua`, erstatt hele `NLC.RecordAward`:

```lua
function NLC.RecordAward(item, awardedTo, awardedBy, boss, category, itemId, exportable, note)
  if exportable == nil then exportable = true end
  local entry = {
    item = item,
    awardedTo = awardedTo,
    awardedBy = awardedBy,
    boss = boss or "Unknown",
    category = category or "upgrade",
    timestamp = time(),
  }
  -- Settes kun når den finnes, så eksisterende oppføringer i SavedVariables
  -- ikke får en tom note-nøkkel de aldri hadde.
  if note and note ~= "" then entry.note = note end

  table.insert(NLC.db.lootHistory, entry)
  if exportable then
    -- Only real player awards are exported to the website. Disenchant/Bank/Free are not.
    table.insert(NLC.db.pendingExport, entry)
  end

  -- Add to pending trades (so the item can still be traded onward)
  local id = itemId or C_Item.GetItemInfoInstant(item)
  NLC.Trade.Add(item, id, awardedTo, awardedBy, boss, category)
end
```

- [ ] **Step 2: Verifiser at ingen kallsted brytes**

```bash
cd nordavind-addon && grep -rn "RecordAward(" NordavindLC/
```

Forventet: to treff — `Council.Award` (7 argumenter, `note` blir `nil`) og `Council.AwardSpecial` (7 argumenter, `exportable = false`). Begge fungerer uendret siden `note` er siste parameter.

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/Core.lua
git commit -m "feat(core): RecordAward tar imot note

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Stemmetilstand og comms

**Files:**
- Modify: `nordavind-addon/NordavindLC/Council.lua` (ny seksjon nederst, ved siden av roll-off)
- Modify: `nordavind-addon/NordavindLC/Comms.lua:130-157` (nye msgType-grener)

**Interfaces:**
- Consumes: `NLC.Comms.Send(msgType, data)`, `NLC.isOfficer`, `NLC.Council.GetActiveSessions()`.
- Produces:
  - `NLC.Council.StartVote(sessionIdx, ballot)` — `ballot` er en array av spillernavn (strenger)
  - `NLC.Council.CastVote(sessionIdx, choice)` — `choice` er et spillernavn
  - `NLC.Council.GetVoteState()` → `_vote`-tabellen (`{ active, sessionIdx, ballot, results, officers }`)
  - `NLC.Council.GetVoteTally()` → `nil` eller `{ rows = { { name, count, voters } }, cast, officers }`, sortert synkende på `count`
  - `NLC.Council.ClearVote()`
  - `NLC.Council.OnVoteStart(sender, data)`, `OnVoteAck(sender)`, `OnVoteCast(sender, data)`

- [ ] **Step 1: Legg stemmetilstanden i `Council.lua`**

Legg til nederst i `NordavindLC/Council.lua`:

```lua
-- ============================================================
-- Officer-avstemming
--
-- Rådgivende: lederen deler ut som før, men når en avstemming er aktiv kreves
-- en begrunnelse, og stemmetallet følger itemet til databasen.
--
-- NLC.isOfficer avgjøres lokalt på hver klient (se Core.lua), så en raider kan
-- teknisk sett stemme ved å endre egne SavedVariables. Vi låser ikke dette —
-- det er et guild-addon, ikke en sikkerhetsgrense — men opptellingen viser
-- navn, slik at et misbruk blir synlig i stedet for skjult.
-- ============================================================

local _vote = { active = false, sessionIdx = nil, ballot = {}, results = {}, officers = {} }

function NLC.Council.GetVoteState() return _vote end

function NLC.Council.ClearVote()
  _vote = { active = false, sessionIdx = nil, ballot = {}, results = {}, officers = {} }
end

-- Lederen starter. Egen kringkasting kommer tilbake til oss selv, så vi blir
-- talt med blant officers og får stemmevinduet på lik linje med de andre.
function NLC.Council.StartVote(sessionIdx, ballot)
  if not NLC.isOfficer or not UnitIsGroupLeader("player") then return end
  if #ballot < 2 then
    NLC.Utils.Print("Legg minst to kandidater på stemmeseddelen.")
    return
  end
  _vote = { active = true, sessionIdx = sessionIdx, ballot = ballot, results = {}, officers = {} }
  NLC.Comms.Send("VOTE_START", { sessionIdx = sessionIdx, ballot = ballot })
  NLC.Council.AnnounceRW("Officer-avstemming startet — " .. #ballot .. " kandidater")
end

function NLC.Council.OnVoteStart(sender, data)
  if not NLC.isOfficer then return end
  NLC.Comms.Send("VOTE_ACK", { sessionIdx = data.sessionIdx })
  if NLC.UI.ShowVotePopup then
    NLC.UI.ShowVotePopup(data.sessionIdx, data.ballot)
  end
end

function NLC.Council.OnVoteAck(sender, data)
  if not _vote.active or data.sessionIdx ~= _vote.sessionIdx then return end
  local name = sender:match("^([^-]+)") or sender
  _vote.officers[name] = true
  NLC.Council.RefreshVoteUI()
end

function NLC.Council.CastVote(sessionIdx, choice)
  NLC.Comms.Send("VOTE_CAST", { sessionIdx = sessionIdx, choice = choice })
end

function NLC.Council.OnVoteCast(sender, data)
  if not _vote.active or data.sessionIdx ~= _vote.sessionIdx then return end
  local name = sender:match("^([^-]+)") or sender
  -- Ny stemme fra samme avsender overskriver forrige, så feilklikk kan rettes.
  _vote.results[name] = data.choice
  NLC.Council.RefreshVoteUI()
end

-- Tegner wizarden på nytt hvis den står åpen på itemet det stemmes over.
function NLC.Council.RefreshVoteUI()
  if not (NLC.UI.IsWizardOpen and NLC.UI.IsWizardOpen()) then return end
  NLC.Theme.Debounce("vote-refresh", 0.5, function()
    local sessions = NLC.Council.GetActiveSessions()
    NLC.UI.ShowWizard(sessions, NLC.Council.GetWizardIndex())
  end)
end

function NLC.Council.GetVoteTally()
  if not _vote.active then return nil end

  local counts, voters = {}, {}
  for voter, choice in pairs(_vote.results) do
    counts[choice] = (counts[choice] or 0) + 1
    voters[choice] = voters[choice] or {}
    table.insert(voters[choice], voter)
  end

  local rows = {}
  for _, name in ipairs(_vote.ballot) do
    local v = voters[name] or {}
    table.sort(v)
    table.insert(rows, { name = name, count = counts[name] or 0, voters = v })
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)

  local cast = 0
  for _ in pairs(_vote.results) do cast = cast + 1 end
  local officers = 0
  for _ in pairs(_vote.officers) do officers = officers + 1 end

  return { rows = rows, cast = cast, officers = officers }
end

-- "officer-avstemming 3-2-1" — stemmetallet i synkende rekkefølge.
function NLC.Council.FormatVoteTally()
  local tally = NLC.Council.GetVoteTally()
  if not tally then return nil end
  local parts = {}
  for _, row in ipairs(tally.rows) do
    table.insert(parts, tostring(row.count))
  end
  return "officer-avstemming " .. table.concat(parts, "-")
end
```

- [ ] **Step 2: Rut meldingene i `Comms.lua`**

I `NordavindLC/Comms.lua`, legg til tre grener rett før `elseif msgType == "VERSION_CHECK" then`:

```lua
  elseif msgType == "VOTE_START" then
    if NLC.Council.OnVoteStart then
      NLC.Council.OnVoteStart(sender, data)
    end

  elseif msgType == "VOTE_ACK" then
    if not NLC.isOfficer then return end
    if NLC.Council.OnVoteAck then
      NLC.Council.OnVoteAck(sender, data)
    end

  elseif msgType == "VOTE_CAST" then
    if not NLC.isOfficer then return end
    if NLC.Council.OnVoteCast then
      NLC.Council.OnVoteCast(sender, data)
    end
```

`VOTE_ACK` og `VOTE_CAST` gates på `isOfficer` fordi kun lederens klient teller opp — raidere skal ikke bruke minne på tilstand de aldri viser.

- [ ] **Step 3: Verifiser opplasting og navn**

```bash
cd nordavind-addon
grep -n "VOTE_" NordavindLC/Comms.lua
grep -n "function NLC.Council.OnVote\|function NLC.Council.StartVote\|function NLC.Council.CastVote" NordavindLC/Council.lua
```

Forventet: tre `VOTE_`-grener i Comms, og at hvert `NLC.Council.On*`-navn Comms kaller finnes i Council. Sjekk at `NLC.Theme.Debounce` finnes (`grep -n "function NLC.Theme.Debounce" NordavindLC/UI/Theme.lua`) — `Council.lua` lastes før `UI/Theme.lua`, men `RefreshVoteUI` kalles først ved kjøretid, så det er trygt.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/Council.lua NordavindLC/Comms.lua
git commit -m "feat(council): stemmetilstand og comms for officer-avstemming

Raadgivende avstemming som speiler roll-off-mekanikken: kringkast, samle
svar, tell opp hos lederen. Ny stemme fra samme avsender overskriver
forrige. Opptellingen viser navn, siden isOfficer avgjoeres lokalt.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Stemmeseddel og opptelling i wizarden

**Files:**
- Modify: `nordavind-addon/NordavindLC/UI/RankingFrame.lua`

**Interfaces:**
- Consumes: `NLC.Council.StartVote`, `GetVoteState`, `GetVoteTally`, `CastVote`, `ClearVote`, `NLC.Theme.CreateButton`, `NLC.Theme.ShowMenu`, `NLC.Theme.ApplyBackdrop`, `NLC.Theme.CreateTitleBar`.
- Produces: `NLC.UI.ShowVotePopup(sessionIdx, ballot)` — stemmevinduet officers ser. `NLC.UI.ShowBallotBuilder(session)` — lederens seddel.

- [ ] **Step 1: Legg avstemmingsknappen i knapperaden**

I `NordavindLC/UI/RankingFrame.lua`, rett etter `rankFrame.specialBtn`-blokka (slutter med `end)` rundt linje 122), legg til:

```lua
    -- Officer-avstemming — kun lederen, og kun når det finnes noen å stemme over.
    rankFrame.voteBtn = T.CreateButton(rankFrame, 200, 34, "Be om officer-avstemming")
    rankFrame.voteBtn:SetPoint("BOTTOMLEFT", 320, 16)
    rankFrame.voteBtn:SetScript("OnClick", function()
      local sessions = NLC.Council.GetActiveSessions()
      local session = sessions[NLC.Council.GetWizardIndex()]
      if session then NLC.UI.ShowBallotBuilder(session) end
    end)
```

Rett etter at `rankFrame` er bygget ferdig i `ShowWizard`, skjul knappen for alle andre enn lederen:

```lua
  if rankFrame.voteBtn then
    if UnitIsGroupLeader("player") then rankFrame.voteBtn:Show() else rankFrame.voteBtn:Hide() end
  end
```

- [ ] **Step 2: Bygg stemmeseddelen**

Legg til i samme fil:

```lua
-- Lederens stemmeseddel: alle kandidater er avkrysset som utgangspunkt, så man
-- fjerner de uaktuelle i stedet for å bygge lista fra bunnen midt i et raid.
local ballotFrame
function NLC.UI.ShowBallotBuilder(session)
  if not ballotFrame then
    ballotFrame = CreateFrame("Frame", "NordavindLCBallot", UIParent, "BackdropTemplate")
    ballotFrame:SetSize(340, 420)
    ballotFrame:SetPoint("CENTER")
    ballotFrame:SetFrameStrata("DIALOG")
    ballotFrame:SetMovable(true)
    ballotFrame:EnableMouse(true)
    ballotFrame:RegisterForDrag("LeftButton")
    ballotFrame:SetScript("OnDragStart", ballotFrame.StartMoving)
    ballotFrame:SetScript("OnDragStop", ballotFrame.StopMovingOrSizing)
    T.ApplyBackdrop(ballotFrame)
    T.CreateTitleBar(ballotFrame, "Officer-avstemming")
    ballotFrame.rows = {}
    ballotFrame.extra = {}
  end

  ballotFrame.session = session
  ballotFrame.checked = {}

  for _, r in ipairs(ballotFrame.rows) do r:Hide() end
  wipe(ballotFrame.rows)

  local y = -44
  local function addRow(name, label)
    local row = CreateFrame("CheckButton", nil, ballotFrame, "UICheckButtonTemplate")
    row:SetSize(24, 24)
    row:SetPoint("TOPLEFT", 16, y)
    row:SetChecked(true)
    ballotFrame.checked[name] = true
    row:SetScript("OnClick", function(self)
      ballotFrame.checked[name] = self:GetChecked() and true or nil
    end)
    local txt = ballotFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", row, "RIGHT", 6, 0)
    txt:SetText(label)
    -- Navnet lagres på raden. Å parse det ut av etiketten igjen ville brukket
    -- første gang noen får et mellomrom eller en farge-kode i visningsteksten.
    row.playerName = name
    table.insert(ballotFrame.rows, row)
    y = y - 28
  end

  for _, c in ipairs(session.ranked or {}) do
    addRow(c.name, string.format("%s  |cff888888(%s, %.1fp)|r", c.name, c.category or "?", c.score or 0))
  end
  for _, name in ipairs(ballotFrame.extra) do
    addRow(name, name .. "  |cff888888(lagt til)|r")
  end

  if not ballotFrame.addBtn then
    ballotFrame.addBtn = T.CreateButton(ballotFrame, 150, 28, "+ Legg til spiller")
    ballotFrame.addBtn:SetPoint("BOTTOMLEFT", 16, 54)
    ballotFrame.addInput = CreateFrame("EditBox", nil, ballotFrame, "InputBoxTemplate")
    ballotFrame.addInput:SetSize(140, 24)
    ballotFrame.addInput:SetPoint("BOTTOMRIGHT", -16, 56)
    ballotFrame.addInput:SetAutoFocus(false)
    ballotFrame.addBtn:SetScript("OnClick", function()
      local n = ballotFrame.addInput:GetText():match("^%s*(.-)%s*$")
      if n and n ~= "" then
        table.insert(ballotFrame.extra, n)
        ballotFrame.addInput:SetText("")
        NLC.UI.ShowBallotBuilder(ballotFrame.session)
      end
    end)

    ballotFrame.startBtn = T.CreateButton(ballotFrame, 150, 30, "Start avstemming")
    ballotFrame.startBtn:SetPoint("BOTTOMLEFT", 16, 16)
    ballotFrame.startBtn:SetScript("OnClick", function()
      local ballot = {}
      for _, r in ipairs(ballotFrame.rows) do
        if ballotFrame.checked[r.playerName] then table.insert(ballot, r.playerName) end
      end
      NLC.Council.StartVote(ballotFrame.session.sessionIdx, ballot)
      ballotFrame:Hide()
    end)

    ballotFrame.cancelBtn = T.CreateButton(ballotFrame, 100, 30, "Avbryt")
    ballotFrame.cancelBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    ballotFrame.cancelBtn:SetScript("OnClick", function()
      wipe(ballotFrame.extra)
      ballotFrame:Hide()
    end)
  end

  ballotFrame:Show()
end
```

- [ ] **Step 3: Bygg stemmevinduet officers ser**

```lua
-- Officers får dette når lederen starter. Ett klikk per navn; ny stemme
-- overskriver forrige, så feilklikk kan rettes uten å spørre lederen.
local votePopup
function NLC.UI.ShowVotePopup(sessionIdx, ballot)
  if not votePopup then
    votePopup = CreateFrame("Frame", "NordavindLCVote", UIParent, "BackdropTemplate")
    votePopup:SetSize(280, 360)
    votePopup:SetPoint("CENTER", 320, 0)
    votePopup:SetFrameStrata("DIALOG")
    votePopup:SetMovable(true)
    votePopup:EnableMouse(true)
    votePopup:RegisterForDrag("LeftButton")
    votePopup:SetScript("OnDragStart", votePopup.StartMoving)
    votePopup:SetScript("OnDragStop", votePopup.StopMovingOrSizing)
    T.ApplyBackdrop(votePopup)
    T.CreateTitleBar(votePopup, "Hvem skal ha itemet?")
    votePopup.btns = {}
  end

  for _, b in ipairs(votePopup.btns) do b:Hide() end
  wipe(votePopup.btns)

  local y = -44
  for _, name in ipairs(ballot) do
    local b = T.CreateButton(votePopup, 240, 28, name)
    b:SetPoint("TOPLEFT", 20, y)
    b:SetScript("OnClick", function()
      NLC.Council.CastVote(sessionIdx, name)
      NLC.Utils.Print("Stemte på " .. name .. ".")
      votePopup:Hide()
    end)
    table.insert(votePopup.btns, b)
    y = y - 32
  end

  votePopup:Show()
end
```

- [ ] **Step 4: Vis opptellingen i wizarden**

I `ShowWizard`, rett før knappene oppdateres, legg til en opptellingsblokk:

```lua
  -- Opptelling — kun hos lederen, og kun for itemet det faktisk stemmes over.
  local tally = NLC.Council.GetVoteTally()
  local vs = NLC.Council.GetVoteState()
  if not rankFrame.voteText then
    rankFrame.voteText = rankFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rankFrame.voteText:SetPoint("BOTTOMLEFT", 20, 58)
    rankFrame.voteText:SetJustifyH("LEFT")
  end
  local session = sessions[index]
  if tally and session and vs.sessionIdx == session.sessionIdx then
    local lines = { "|cffC8A45COfficer-avstemming|r" }
    for _, row in ipairs(tally.rows) do
      table.insert(lines, string.format("  %s  %d  |cff888888%s|r",
        row.name, row.count, table.concat(row.voters, ", ")))
    end
    table.insert(lines, string.format("|cff888888%d av %d officers har stemt|r", tally.cast, tally.officers))
    rankFrame.voteText:SetText(table.concat(lines, "\n"))
    rankFrame.voteText:Show()
  else
    rankFrame.voteText:Hide()
  end
```

- [ ] **Step 5: Verifiser**

```bash
cd nordavind-addon
grep -n "ShowVotePopup\|ShowBallotBuilder\|voteText\|voteBtn" NordavindLC/UI/RankingFrame.lua
```

Forventet: `ShowVotePopup` og `ShowBallotBuilder` definert som `NLC.UI.*`, og `voteBtn`/`voteText` opprettet. Bekreft at `T` er alias for `NLC.Theme` øverst i fila (`grep -n "local T" NordavindLC/UI/RankingFrame.lua`) — koden over forutsetter det.

- [ ] **Step 6: Commit**

```bash
git add NordavindLC/UI/RankingFrame.lua
git commit -m "feat(wizard): stemmeseddel, stemmevindu og opptelling

Lederen bygger seddelen (alle avkrysset som utgangspunkt, kan legge til
en som mangler), officers stemmer med ett klikk, og opptellingen vises
i wizarden med navn paa hvem som stemte hva.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Begrunnelse og award-integrasjon

Uten dette steget er avstemmingen bare pynt — stemmetallet når aldri databasen.

**Files:**
- Modify: `nordavind-addon/NordavindLC/UI/RankingFrame.lua` (begrunnelse-popup)
- Modify: `nordavind-addon/NordavindLC/Council.lua:315-354` (`Award`)

**Interfaces:**
- Consumes: `NLC.Council.FormatVoteTally()`, `NLC.RecordAward(..., note)` fra Task 2.
- Produces: `NLC.UI.ShowReasonPopup(playerName, onConfirm)` — kaller `onConfirm(reasonText)` når lederen bekrefter.

- [ ] **Step 1: Bygg begrunnelse-popupen**

Legg til i `NordavindLC/UI/RankingFrame.lua`:

```lua
-- Begrunnelsen er påkrevd: regelteksten lover at unntaket logges *med* grunn.
-- Uten den er "logges" bare en RW-melding som ruller vekk.
local reasonPopup
function NLC.UI.ShowReasonPopup(playerName, onConfirm)
  if not reasonPopup then
    reasonPopup = CreateFrame("Frame", "NordavindLCReason", UIParent, "BackdropTemplate")
    reasonPopup:SetSize(400, 170)
    reasonPopup:SetPoint("CENTER")
    reasonPopup:SetFrameStrata("FULLSCREEN_DIALOG")
    reasonPopup:EnableMouse(true)
    T.ApplyBackdrop(reasonPopup)
    T.CreateTitleBar(reasonPopup, "Begrunnelse for unntaket")

    reasonPopup.label = reasonPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reasonPopup.label:SetPoint("TOPLEFT", 20, -44)

    reasonPopup.input = CreateFrame("EditBox", nil, reasonPopup, "InputBoxTemplate")
    reasonPopup.input:SetSize(356, 26)
    reasonPopup.input:SetPoint("TOPLEFT", 22, -72)
    reasonPopup.input:SetAutoFocus(true)

    reasonPopup.hint = reasonPopup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    reasonPopup.hint:SetPoint("TOPLEFT", 20, -102)
    reasonPopup.hint:SetText("Kort og konkret — dette havner i loot-historikken.")

    reasonPopup.okBtn = T.CreateButton(reasonPopup, 120, 30, "Tildel")
    reasonPopup.okBtn:SetPoint("BOTTOMRIGHT", -20, 16)
    reasonPopup.okBtn:SetScript("OnClick", function()
      local txt = reasonPopup.input:GetText():match("^%s*(.-)%s*$")
      if not txt or txt == "" then
        NLC.Utils.Print("Begrunnelse er påkrevd når itemet gis utenom lista.")
        return
      end
      reasonPopup:Hide()
      if reasonPopup.cb then reasonPopup.cb(txt) end
    end)

    reasonPopup.cancelBtn = T.CreateButton(reasonPopup, 100, 30, "Avbryt")
    reasonPopup.cancelBtn:SetPoint("BOTTOMLEFT", 20, 16)
    reasonPopup.cancelBtn:SetScript("OnClick", function() reasonPopup:Hide() end)
  end

  reasonPopup.label:SetText("Itemet gis til |cffC8A45C" .. playerName .. "|r utenom lista.")
  reasonPopup.input:SetText("")
  reasonPopup.cb = onConfirm
  reasonPopup:Show()
end
```

- [ ] **Step 2: Del `Award` i to**

I `NordavindLC/Council.lua`, erstatt `NLC.Council.Award` med en variant som spør om begrunnelse når en avstemming er aktiv for itemet:

```lua
function NLC.Council.Award(playerName)
  if not NLC.isOfficer or not UnitIsGroupLeader("player") or #activeSessions == 0 then return end

  local session = activeSessions[currentWizardIndex]
  if not session then return end

  -- Er det stemt over akkurat dette itemet, kreves en begrunnelse før noe skjer.
  if _vote.active and _vote.sessionIdx == session.sessionIdx and NLC.UI.ShowReasonPopup then
    NLC.UI.ShowReasonPopup(playerName, function(reason)
      NLC.Council.DoAward(playerName, (NLC.Council.FormatVoteTally() or "officer-avstemming") .. " — " .. reason)
    end)
    return
  end

  NLC.Council.DoAward(playerName, nil)
end

function NLC.Council.DoAward(playerName, note)
  local session = activeSessions[currentWizardIndex]
  if not session then return end

  -- Find the player's interest category from ranking
  local category = "upgrade"
  if session.ranked then
    for _, c in ipairs(session.ranked) do
      if c.name == playerName then
        category = c.category or "upgrade"
        break
      end
    end
  end

  NLC.Comms.Send("AWARD", { sessionIdx = session.sessionIdx, itemLink = session.itemLink, playerName = playerName, category = category })
  NLC.RecordAward(session.itemLink, playerName, UnitName("player"), session.boss, category, session.itemId, true, note)
  NLC.Utils.Print(session.itemLink .. " awarded to " .. playerName .. " (" .. category .. ")")

  -- Track weekly loot count in SavedVariables (resets each Wednesday).
  -- Kun straffbare kategorier telles — se NLC.Scoring.CountsAsLoot.
  if NLC.Scoring.CountsAsLoot(category) then
    NLC.db.weeklyLoot = NLC.db.weeklyLoot or { resetTimestamp = 0, counts = {} }
    NLC.db.weeklyLoot.counts[playerName] = (NLC.db.weeklyLoot.counts[playerName] or 0) + 1
  end

  local msg = session.itemLink .. " tildelt " .. playerName .. " (" .. (CAT_NO[category] or category) .. ")"
  if note then msg = msg .. " — " .. note end
  NLC.Council.AnnounceRW(msg)

  for i, s in ipairs(activeSessions) do
    if i ~= currentWizardIndex and s.phase == "ranking" then
      s.ranked = NLC.Council.BuildRanking(s)
    end
  end

  session.phase = "awarded"
  NLC.Council.ClearRoll()
  NLC.Council.ClearVote()
  NLC.Council.AdvanceWizard()
end
```

**Merk:** `_vote` er en `local` deklarert nederst i `Council.lua` (Task 3), mens `Award` ligger lenger opp. Lua-upvalues må deklareres **før** funksjonen som leser dem. Flytt derfor `local _vote = ...`-linja opp til de andre modul-lokalene øverst i fila (ved siden av `local activeSessions = {}`), og la resten av avstemmingsseksjonen ligge nederst. Uten dette leser `Award` en global `nil` og avstemmingen slår aldri inn.

- [ ] **Step 3: Verifiser upvalue-rekkefølgen**

```bash
cd nordavind-addon
grep -n "^local _vote\|^local activeSessions\|function NLC.Council.Award" NordavindLC/Council.lua
```

Forventet: linjenummeret for `local _vote` er **lavere** enn linjenummeret for `function NLC.Council.Award`. Er det ikke det, virker ikke avstemmingen — dette er samme feilen som ble gjort en gang før i dette repoet.

- [ ] **Step 4: Commit**

```bash
git add NordavindLC/Council.lua NordavindLC/UI/RankingFrame.lua
git commit -m "feat(council): paakrevd begrunnelse og note paa award ved avstemming

Award deles i to: naar en avstemming er aktiv for itemet spoer vi om grunn
foerst, og stemmetallet + grunnen foelger itemet til pendingExport og
videre til databasen. RW-kunngjoeringen faar samme tekst.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: `/nordlc test` seeder en avstemming

Eneste måten å kjøre flyten uten et raid. Uten dette er Task 3–5 helt uverifisert før 18. august.

**Files:**
- Modify: `nordavind-addon/NordavindLC/Core.lua` (test-kommandoen, rundt linje 382)

**Interfaces:**
- Consumes: `NLC.Council.GetVoteState()`, `NLC.Council.RefreshVoteUI()`.
- Produces: `/nordlc testvote` — seeder officers og stemmer uten comms.

- [ ] **Step 1: Legg til underkommandoen**

I `NordavindLC/Core.lua`, i slash-håndtereren rett etter `elseif cmd == "test" then`-blokka, legg til:

```lua
  elseif cmd == "testvote" then
    -- Seeder en avstemming direkte i tilstanden, uten comms, så hele flyten
    -- (seddel → opptelling → begrunnelse → note) kan kjøres alene offline.
    local sessions = NLC.Council.GetActiveSessions()
    local idx = NLC.Council.GetWizardIndex()
    local session = sessions[idx]
    if not session then
      NLC.Utils.Print("Ingen aktiv session — kjør /nordlc test først.")
      return
    end
    local ballot = {}
    for _, c in ipairs(session.ranked or {}) do table.insert(ballot, c.name) end
    if #ballot < 2 then
      NLC.Utils.Print("Trenger minst to kandidater — kjør /nordlc test først.")
      return
    end
    NLC.Council.StartVote(session.sessionIdx, ballot)
    local vs = NLC.Council.GetVoteState()
    vs.officers = { Fisk = true, Braxina = true, Bell = true, Gyddian = true }
    vs.results = { Fisk = ballot[1], Braxina = ballot[1], Bell = ballot[2] }
    NLC.Council.RefreshVoteUI()
    NLC.Utils.Print("Testavstemming seedet: 3 av 4 officers har stemt.")
```

- [ ] **Step 2: Kjør flyten i spillet**

Kopier addonet inn og test:

```bash
cd nordavind-addon
cp -r NordavindLC/* "/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/NordavindLC/"
```

I spillet, med `/reload` først:

1. `/nordlc test` — seeder kandidater og åpner wizarden
2. `/nordlc testvote` — seeder avstemmingen
3. Kontroller at opptellingen vises med navn og «3 av 4 officers har stemt»
4. Trykk **Tildel** på en kandidat → begrunnelse-popup skal komme
5. Prøv å bekrefte med tom tekst → skal avvises med melding
6. Skriv en grunn og bekreft
7. `/nordlc history` → oppføringen skal ha noten
8. `/nordlc status` → «Export: N awards» skal ha økt

Test også lederens side: trykk **Be om officer-avstemming**, fjern en avkryssing, legg til et navn, start.

- [ ] **Step 3: Commit**

```bash
git add NordavindLC/Core.lua
git commit -m "feat(test): /nordlc testvote seeder en avstemming offline

Eneste maaten aa kjoere hele flyten uten et raid: seddel, opptelling,
paakrevd begrunnelse og note paa award.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Nettsiden viser unntaket

**Files:**
- Modify: `nordavind-web/app/api/loot/history/route.ts`
- Modify: `nordavind-web/app/loot/loot-client.tsx`

**Interfaces:**
- Consumes: `LootDrop.note` fra Task 1.
- Produces: `note` i historikk-API-svaret, og en unntaksmarkør i historikk-visningen.

- [ ] **Step 1: Ta med feltet i API-svaret**

I `nordavind-web/app/api/loot/history/route.ts`, i `drops.map`-blokka, legg `note` inn i det returnerte objektet rett etter `date`:

```ts
      date: d.createdAt.toISOString(),
      note: d.note ?? null,
    };
  });
```

`findMany` har ingen `select`, så feltet følger allerede med fra databasen — kun utplukket mangler.

- [ ] **Step 2: Utvid typen i klienten**

I `nordavind-web/app/loot/loot-client.tsx`, i `interface HistoryItem` (rundt linje 65), legg til etter `date: string;`:

```ts
  date: string;
  note: string | null;
}
```

- [ ] **Step 3: Vis unntaket**

Historikken er en tabell, så noten legges under itemnavnet i første celle. Erstatt item-cella (rundt linje 155):

```tsx
                    <td className="py-2 pr-3 text-purple-300 font-medium">
                      {item.item}
                      {item.note && (
                        <div className="text-[var(--muted2)] text-xs font-normal mt-0.5">
                          ⚠️ {item.note}
                        </div>
                      )}
                    </td>
```

- [ ] **Step 4: Verifiser**

```bash
cd nordavind-web && npx tsc --noEmit && npm run build
```

Forventet: begge exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/api/loot/history/route.ts app/loot/loot-client.tsx
git commit -m "feat(loot): vis avstemmings-unntak i historikken

Uten dette staar et item gitt utenom lista som en helt vanlig rad, og
"logges" betyr i praksis at noen skriver det ned.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Kjent hull i verifiseringen

Spec-en sier at testene skal dekke «at API-et skriver det». Det gjør de ikke, og
det er verdt å si rett ut framfor å late som.

`nordavind-web` kjører `node --test lib/*.test.ts` — det finnes ingen
rute-tester og ingen testdatabase. Å bygge det opp for ett felt er ute av
proporsjon. `note` er derfor dekket slik:

- **companion → API-kall:** ekte test (Task 1)
- **API-rute → databasen:** kun typecheck. Første ekte award bekrefter resten.

Den som utfører planen skal **ikke** finne på å teste dette mot produksjons-API-et
— det ville skrevet ekte loot-rader.

## Etter planen

- **In-game raid-test.** Comms mellom ekte klienter kan ikke verifiseres offline: at officers faktisk får stemmevinduet, at `VOTE_ACK` gir riktig nevner, og at køing under encounter flusher stemmene etterpå. Dette kommer i tillegg til de fire portene som allerede står åpne.
- **CurseForge-release** før 18. august, ellers har officers en addon uten avstemming — mens regelteksten lover den.
- **Companion må bygges og reinstalleres** (`npm run dist` + kjør installeren), ellers når `note` aldri API-et.
