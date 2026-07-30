# Officer-avstemming — design

**Dato:** 2026-07-30
**Status:** Godkjent, ikke implementert

## Mål

Gi officers et verktøy for det ene unntaket sesong 2-reglene åpner for: når lista
er åpenbart feil og feilen ikke lar seg rette der og da, stemmer officers over
hvem itemet skal gå til — åpent, og med begrunnelsen lagret.

## Bakgrunn

Regelteksten (`nordavind-web/docs/sesong2-regler-discord.md`) lover:

> Vi følger lista punkt for punkt. [...] Er det en åpenbar feil i grunnlaget
> [...] retter vi feilen og lar lista regne på nytt. Lar feilen seg ikke rette
> der og da, tar officers en **avstemming** på hvem itemet skal gå til. Det
> skjer åpent i raidet, avgjørelsen sies høyt, og den logges sammen med
> begrunnelsen.

To av tre løfter er innfridd i dag. Retting av grunnlaget finnes: `/oppmote rett`
for oppmøte, `/roster/link` for manglende karakterkobling, og addonets
høyreklikk-meny for feil kategori. Avstemmingen finnes ikke, og «logges» ville i
praksis betydd at noen skriver det ned manuelt.

En award gitt utenom lista blir i dag en helt vanlig rad i loot-historikken,
uten spor av at den var et unntak. Det er det motsatte av etterprøvbarhet.

## Avgjørelser

| Spørsmål | Valg | Hvorfor |
|---|---|---|
| Bindende? | **Rådgivende.** Lederen deler ut. | Én hånd på rattet. En feilstemming kan stoppes før itemet er borte. |
| Stemmeseddel | Kandidatene på lista, + mulighet til å legge til | Dekker tilfellet der feilen er at noen ikke kom med i det hele tatt |
| Logging | Helt til databasen | Ellers er «logges» bare en RW-melding som ruller vekk |
| Tidsfrist | Ingen | Står til lederen deler ut eller avbryter |
| Uavgjort | Ingen automatikk | Rådgivende — lederen avgjør |

## Arkitektur

Bygger på roll-off-mekanikken i `Council.lua`, som løser nesten samme problem:
kringkast, samle svar, vis resultat. Samme livssyklus, samme comms-vei.

### Flyt

1. **Start.** Lederen trykker «Be om officer-avstemming» i wizarden. En
   stemmeseddel åpnes: avkryssing over kandidatene i `session.ranked`, pluss
   «Legg til spiller» for en som mangler helt. **Alle kandidater er avkrysset
   som utgangspunkt** — lederen fjerner dem som åpenbart ikke er aktuelle, i
   stedet for å bygge seddelen fra bunnen.

   Knappen krever `UnitIsGroupLeader`, samme gate som `Council.Award`. Det er
   den som kjører councilet som starter avstemmingen; øvrige officers stemmer.

2. **Kringkasting.** `NLC.Comms.Send("VOTE_START", { sessionIdx, itemLink, ballot })`.
   Går over `RAID` som all annen comms, men kun klienter med `NLC.isOfficer`
   tegner opp stemmevinduet. Samme klienter svarer med `VOTE_ACK`, slik at
   lederen får nevneren til «4 av 5 officers har stemt».

3. **Stemming.** Officer klikker et navn → `VOTE_CAST` med `{ sessionIdx, choice }`.
   Ny stemme fra samme avsender overskriver forrige, så feilklikk kan rettes.

4. **Opptelling.** Kun på lederens klient. `_vote.results[avsender] = valg`.
   Vises live i wizarden med **navn på hvem som stemte hva**.

   Dette er et bevisst valg. `NLC.isOfficer` avgjøres lokalt på hver klient
   (`Core.lua:134-141`: raid leader, navn i officer-lista, eller gildrank ≤ 2),
   så en raider kan teknisk sett stemme ved å endre sin egen SavedVariables.
   Vi låser ikke dette — det er et guild-addon, ikke en sikkerhetsgrense — men
   ved å vise navn blir et misbruk synlig i stedet for skjult.

5. **Tildeling.** Lederen trykker Award som vanlig. Er en avstemming aktiv for
   itemet, ber addonet om en kort begrunnelse først. **Påkrevd** — reglene lover
   at unntaket logges *med* begrunnelse.

6. **Kunngjøring.** `NLC.Council.AnnounceRW` med stemmetall og grunn.

7. **Lagring.** Notatet følger itemet hele veien til databasen.

### Notatets vei

| Lag | Endring |
|---|---|
| `Core.lua` | `NLC.RecordAward(..., note)` legger `note` på `lootHistory` og `pendingExport` |
| `companion/lib/api-client.js` | `awardLoot` videresender `note` |
| `nordavind-web` `POST /api/loot/addon` | tar imot og skriver `note` |
| `nordavind-bot` prisma | `LootDrop.note String?` + migrasjon |
| `nordavind-web` loot-historikk | viser unntaket |

Alt er nullable og additivt. Gammel companion mot ny API fungerer uendret —
samme egenskap som `category`-feltet har.

Migrasjonen hører hjemme i `nordavind-bot/prisma/migrations/`, med
`ADD COLUMN IF NOT EXISTS`.

## Feilhåndtering

- **Comms sperret under encounter.** `NLC.Comms.Send` køer allerede alt mens
  `ADDON_RESTRICTION_STATE_CHANGED` er aktiv og flusher når den løftes. Stemmer
  arver denne oppførselen gratis.
- **Stemme på en som har forlatt raidet.** Telles som normalt; lederen ser det og
  avgjør.
- **`/reload` midt i en avstemming.** Tilstanden ligger i minnet, som roll-offen,
  og går tapt. Avstemmingen må startes på nytt. Bevisst valg — persistering er
  ikke verdt kompleksiteten for noe som skjer sjelden.
- **Award uten aktiv avstemming.** Uendret oppførsel, ingen begrunnelse etterspørres.
- **Companion nede.** `pendingExport` hoper seg opp som før og synkes når den
  starter. Notatet ligger i køen.

## Testing

`node --test` dekker companion- og web-delen: at `note` overlever hele veien fra
parset SavedVariables til API-kall, og at API-et skriver det.

Lua har verken testrunner eller `luac` tilgjengelig i dette miljøet. `/nordlc test`
utvides derfor til å seede en avstemming med fiktive officers, slik at hele flyten
kan kjøres alene offline: stemmeseddel, stemmegivning, opptelling, begrunnelse,
kunngjøring. Det fanger renderings- og logikkfeil.

**Comms mellom ekte klienter kan bare bekreftes i raid** — som de fire andre
portene som allerede står åpne (restriksjons-gating, roll-off, bag-scan, ShowMenu).

## Utenfor omfang

Anonym stemming. Automatisk tildeling til vinneren. Tiebreak. Persistering over
`/reload`. Vekting av stemmer etter rang. Historikk over tidligere avstemminger
utover det som ligger i loot-historikken.

## Berørte filer

**Addon:** `Council.lua` (stemmetilstand, start/cast/tally, award-integrasjon),
`Comms.lua` (VOTE_START / VOTE_ACK / VOTE_CAST), `UI/RankingFrame.lua` (knapp,
stemmeseddel, opptelling), `Core.lua` (`RecordAward` note, `/nordlc test`).

**Companion:** `lib/api-client.js`, `test/`.

**Web:** `app/api/loot/addon/route.ts`, loot-historikk-visning.

**Bot:** `prisma/schema.prisma`, ny migrasjon.

## Se også

- `nordavind-web/docs/sesong2-regler-discord.md` — regelteksten dette innfrir
- `2026-07-07-loot-distribution-flow-design.md` — roll-off og kontekstmeny
