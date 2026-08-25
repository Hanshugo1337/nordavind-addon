# Loot-panelet som hovedvei, ikke som resultat av en timer

**Dato:** 2026-08-25
**Status:** Design, ikke implementert
**Spenner over:** `nordavind-addon` (NordavindLC)
**Forutsetning:** timerfiksen (`ROLL_SETTLE`) skal ha kjørt i et ekte raid først

## Problemet

Panelet er i dag resultatet av en runde som må bli ferdig:

```
ENCOUNTER_END → innsamlingsvindu → vinduet stenger → LOOT_REPORT sendes
   → officeren aggregerer → 10 s stillhet → panelet vises
```

Hvert ledd må lykkes, og hele kjeden er usynlig mens den pågår. Går ett ledd galt —
eller bare tar tid — skjer det ingenting på skjermen, og lederen har ingen måte å se
forskjell på «det kommer straks» og «det kommer aldri».

24.08 var det timeren: rullene meldte 270 sekunder, vinduet stengte på +283 s, og
panelet kom på +293 s. Itemsa lå i baggen fra +36 s. Lederen brukte `/nordlc addall`
på **hver eneste boss**.

Timerfiksen (`ROLL_SETTLE = 45`) korter ned ventinga til ~58 sekunder. Den fjerner
symptomet, men ikke formen: panelet er fortsatt en **port** som alt må vente på.

## Hva RCLootCouncil gjør i stedet

Lest i klienten (`RCLootCouncil/`, ikke kopiert):

- **Ingen innsamlingsvindu.** `ENCOUNTER_END` brukes kun til å ta øyeblikksbilde av
  instansdata og nullstille lista over ikke-handelbare items (`core.lua:1726`).
- **Items legges inn enkeltvis** etter hvert som de oppdages (`AddItem`), og
  sesjonsvinduet vises med det som finnes akkurat da (`ml_core.lua:296`).
- **`autoStart = false` er standard** (`Core/Defaults.lua:101`): vinduet åpner med
  lista, lederen trykker Start selv. Han ser noe med én gang.
- **`SessionFromBags`** lar lederen når som helst åpne en sesjon fra items i baggen —
  en førsteklasses arbeidsflyt, ikke en nødutgang.

Sagt rett ut: **`/nordlc addall` er RCs normalvei.** Hos oss er den redningsplanken.

## Målet

Panelet åpner så snart det første handelbare itemet er funnet, og **vokser** mens
resten kommer inn. Ingen venting, ingen `addall` for å få øye på noe.

Ikke-mål:

- **Fjerne innsamlingsvinduet.** De andre raiderne skal fortsatt rapportere det de
  fanget; vinduet er riktig for *dem*. Det skal bare ikke være porten for lederens
  egne items.
- **Auto-start av council.** Panelet viser og vokser. Lederen bestemmer fortsatt når
  det deles ut — som i dag, og som RCs standardvalg.
- **Endre comms-protokollen.** `LOOT_REPORT` beholdes uendret.

## Designet

Halve maskineriet finnes: `Council.OnLootReport` aggregerer allerede per boss, bygger
videre på det som alt er kommet inn, og tegner panelet på nytt
(`Council.lua:788-822`). To ting stopper et voksende panel:

**1. Lederens egne items går omveien.**
`ScanBags` finner dem sekunder etter killet, men de sendes først når hans eget
innsamlingsvindu stenger. Endring: er jeg officer, mates funnene rett inn i
aggregeringa lokalt — samme inngang som en innkommende `LOOT_REPORT`, bare uten
comms-turen. Rapporten sendes fortsatt når vinduet stenger (uendret for alle andre).

**2. Aggregeringa venter ti sekunder før den viser noe.**
De ti sekundene finnes fordi klientene ikke stenger samtidig, og en pulje som
ERSTATTET forrige ville latt den første rapporten forsvinne. Den begrunnelsen gjelder
**oppdateringer**, ikke førstevisninga. Endring: første batch tegnes straks; senere
batcher beholder debouncen og oppdaterer panelet som allerede står åpent.

Dedup ligger allerede i `_agg` på `itemId:looter`, så samme item kan ikke komme to
ganger uansett hvilken vei det kom inn.

## Hva lederen ser

```
+00:10  Panelet åpner:  «Ravenous Feaster's Fang»                    (1 item)
+00:24  Vokser:         + «Ophidian Fangmail»                        (2 items)
+00:41  Vokser:         + 3 fra Braxinas rapport                     (5 items)
+02:15  Sen rull:       + «Silken Voodoo Drape»                      (6 items)
```

Panelet står åpent hele veien. Nye rader glir inn nederst, og en liten teller i
tittellinja sier «6 items · sist oppdatert 14:23».

## Risiko, og hva som demper den

| Risiko | Demping |
|---|---|
| Lederen deler ut før alt har landet | Telleren og tidsstempelet i tittelen. Rader som kommer etter en utdeling legges til uten å røre det som er delt ut. |
| Panelet blafrer ved hver oppdatering | Kun **nye** rader tegnes; eksisterende rader røres ikke. Debounce beholdes for alt etter første visning. |
| Panelet åpner på et item som ikke skal i council | Filtrene (`erCouncilLoot`, kvalitet, handelstid) kjører som før — de sitter i `ScanBags`, ikke i panelet. |
| Sen rull etter at panelet er lukket | `LOOT_ITEM_ROLL_WON` vekker innsamlingen (bevist i `bagbacklog_harness`, «sen rull vekker»). Panelet gjenåpnes med det nye itemet. |

## Testing

Utvidelser av `tests/lootpanel_harness.lua` og `tests/lootwindow_harness.lua`:

1. **Førstevisning:** item i baggen på +10 s → panelet vist med 1 item, uten at
   innsamlingsvinduet har stengt.
2. **Voksing:** ny `LOOT_REPORT` på +41 s → panelet har 5 items, og den første raden
   er den samme raden (ikke gjenoppbygd).
3. **Ingen dobbeltføring:** samme item via egen bag OG via rapport → 1 rad.
4. **Sen rull:** item på +130 s etter at panelet ble lukket → panelet gjenåpnes.

## Rekkefølge

**Ikke før timerfiksen har kjørt en raidkveld.** Går onsdagen bra med kun `ROLL_SETTLE`
endret, vet vi at den virket. Legges begge ut samtidig, vet vi ingenting — verken ved
suksess eller fiasko. Det var nøyaktig sånn 19.08 gikk galt.

Etter en grønn onsdag: bygg dette, test offline med `/nordlc test`, og la det gå en
kveld til før tag.
