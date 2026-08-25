# Før en tag pushes

Skrevet 2026-08-19, kvelden 1.9.0 tok ned loot-systemet for hele guilden midt i
raidet. Alt under er ting som ville stoppet den kvelden.

Taggen er det som fyrer CurseForge-bygget ut til ~30 mennesker. Den er ikke
angrefri: folk må starte klienten på nytt for å få en ny versjon, og en feil
release koster en raidkveld.

## 1. Testene

```
for h in ranking lootpanel popupcache comms bagbacklog session tiertoken \
         manualscan lootwindow tooltipapi theme lootroll roster \
         errorcapture trade avvisning inaktivlogg aggregering; do
  python -c "from lupa import LuaRuntime; LuaRuntime().execute(open('tests/${h}_harness.lua',encoding='utf-8').read())"
done
```

Alle skal være grønne. `lupa` gir Lua 5.5, spillet gir 5.1 — grep i tillegg for
`goto`, `::label::`, `//`, `<<`, `>>` og ikke-ASCII i identifikatorer.

## 2. API-navn ingen andre bruker

```
python tests/apicheck.py
```

Sammenligner hvert `C_Namespace.Funksjon`-kall vårt mot alle andre addons som
faktisk kjører i klienten. Et navn ingen andre bruker er enten nytt, sjeldent —
eller oppdiktet.

Dette er sjekken som ville avslørt `C_TooltipInfo.GetItemByHyperlink` på ett
sekund. Tretten andre addons brukte `GetHyperlink`; vi var alene om vårt navn.
Kallet var nil, kastet, og tok med seg både bag-skannet og raidernes popup.

Treff er ikke bevis på feil. Hvert treff skal være **lest og forstått**, ikke
avfeid.

## 3. Locals brukt over deklarasjonen

```
python tests/scopecheck.py
```

I Lua ser en funksjon bare locals deklarert **før** den. Kaller du en
`local function` som står lenger nede, slås navnet opp som global, blir nil, og
kallet kaster — først når den linja faktisk kjører.

Den fella har truffet dette addonet tre ganger: `_vote` i `Council.lua`,
`LootDetection.lua` under loot-omskrivingen, og igjen 19.08 da `Register` fikk et
`dbg`-kall. Ingen av dem gir syntaksfeil.

## 4. Interface-nummeret i `.toc`

Sjekk hvilket bygg klienten faktisk kjører (`gx.log` i `Logs/`, eller
`/run print(select(4, GetBuildInfo()))`), og at `## Interface:` inneholder det.

Er nummeret for gammelt, merker WoW addonet **«Out of date» og laster det ikke**.
Det ser ut som om folk mangler addonet — de har det, det kjører bare ikke.
1.8.0 sto på 120001 mens klienten var 12.1.0 (120100).

## 5. In-game røyktest — hver gang, uten unntak

```
/nordlc test        wizard + rangering
/nordlc testvote    avstemming
/nordlc testpopup   interesse-popupen
/nordlc testloot    Loot Detected-panelet
/nordlc addall      ekte items fra din egen bag
```

Testdataene inneholder **ekte item-ID-er og minst én rad med `equipLoc = ""`**
(tier-token). Det er ikke kosmetikk: den raden er den eneste veien inn i
`GetTierTokenArmorType`, og det var den grenen som drepte popupen for alle.
De gamle testdataene brukte oppdiktede ID-er der alle hadde ekte slot — vi kunne
kjørt dem hundre ganger uten å se noe.

Er BugSack stille etter alle fem? Da først går du videre.

## 6. Regelen som ble brutt

**Ingen tag før koden har kjørt i et ekte raid.**

Den sto skrevet før 1.9.0 gikk ut. Taggen ble pushet likevel, og 28 mennesker
fikk kode som aldri hadde sett en boss. Hold en release igjen til den er prøvd —
eller gi zip-en til to-tre raidere først og la dem kjøre en kveld.

## 7. Etter release

`/nordlc diag` viser hva innsamlingen faktisk gjorde, og loggen overlever
`/reload`. Går noe galt neste gang, be om den **før** du begynner å gjette.

To ting ble lagt til 22.08, begge fordi loggen ikke kunne svare på et spørsmål
den burde kunnet svare på:

**Nulltallet har nå alltid en grunn.** «Innsamling stengt | 0 items» betydde før
enten at ingenting droppet eller at filteret kastet alt — samme linje for to helt
ulike tilstander. Nå står det `| avvist: 14 uten handelstid`, og du vet med én
gang hvilken av dem det er. Merk at `IsTradeableBagItem` krever det aktive
2-timers handelsvinduet, ikke bare at itemet er epic: i gammelt innhold uten
handelsvindu avvises alt, og det er ikke en feil.

**`ENCOUNTER_END` logges også når addonet er av.** Registreringen lå i
`Register()`, som kun kalles fra `Activate()` — så grenen «addon er IKKE aktiv»
var død kode, og en hel raidkveld kunne gi null linjer uten at noe var galt.
Den ligger nå i `registrerAlltid()`, som også kalles fra `Unregister()`, siden
`UnregisterAllEvents()` ellers river den ned ved første `Deactivate`.
`START_LOOT_ROLL` ble bevisst IKKE flyttet med: auto-rullen må bli stående bak
`Activate()`, ellers ruller addonet Need eller Pass for deg i tilfeldige pug-raid.
