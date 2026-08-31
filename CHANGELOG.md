# NordavindLC Changelog

## 1.9.5 (2026-09-01)

To endringer, ingen av dem roerer hvordan addonet oppfoerer seg i et raid.

### Handelsflyten logger til diag

Da et item ble staaende som ventende etter en handel 31.08 fantes det ingen
spor: TRADE_SHOW, TRADE_ACCEPT_UPDATE og UI_INFO_MESSAGE skrev ingenting.
Eneste bevis var hva som laa igjen i baggen, og det er for lite til aa skille to
helt ulike feil fra hverandre — samme kveld sto ett item igjen som ventende mens
et annet var borte fra lista uten aa vaere levert.

Loggen viser naa hvem mottakeren ble lest som og fra hvilken av de fire kildene,
hva som laa i vinduet, hvilken gren som kjoerte, og hvilke rader som ble fjernet.
**Ingen atferdsendring** — fiksen kommer naar en raidkveld har gitt data.
Be om `/nordlc diag` etter foerste handel.

### Defensiv-terskelen staar ett sted, og teksten stemmer

`0.8` sto hardkodet i if-en, som en fjerde kopi av tallet nordavind-web har.
Endret man det ene, fikk samme spiller advarsel paa nettsida men ikke i addonet.
Heter naa `DEFENSIVE_WARN_BELOW`, med samme «MAA foelge»-kommentar som
ukesstraffen og sim-poengene.

Teksten var ogsaa feil. «%.1f/fight» leses som antall kast, men tallet er en
ANDEL av knappene spilleren har — nevneren er spec-normalisert paa web-sida, saa
1.5 betyr 150 % av knappene sine, ikke halvannet kast.

⚠️ Krever ny import for at de nye defensiv-tallene skal vises: web regner dem
spec-normalisert fra 31.08, saa en Mage og en Holy Priest faar helt andre tall
enn foer.

## 1.9.4 (2026-08-31)

Tagget FOER in-game roeyktest, paa brukers valg: `RELEASE.md` punkt 5 og 6
hoppet over bevisst, slik som ved 1.9.1 og 1.9.3. Grunnen er at council
leder-only og reconnect ikke kan proeves uten to klienter med samme bygg —
releasen ER maaten resten av officerne faar den paa. Koden proeves i raidet
02.09.

**Krever FULL omstart av WoW, ikke `/reload`.**

### Mottakeren i handelsvinduet leses naa fire veier, og vi SPOER om secret

12.0 gjorde `TradeFrameRecipientNameText:GetText()` til et secret value, og
26.08 kastet det ni ganger midt i raid. Fiksen den gangen isolerte hvert forsoek
i `pcall` og falt tilbake paa `UnitName("NPC")`. To hull sto igjen:

- **`pcall` fanger bare det som KASTER.** Et secret value som lar seg lese, men
  ikke sammenligne senere, slapp gjennom og ga feil mottaker — og da fjernes
  feil gjeld hos feil person. 12.0 har `issecretvalue` nettopp for dette;
  BugGrabber og RCLootCouncil spoer den foer de roerer verdien. Det gjoer vi naa
  ogsaa.
- **Begge navnekildene leser en STRENG.** Stenger spillet den ene, er sjansen
  stor for at den andre gaar samme vei — det er tredje navne- eller
  avstands-API som forsvinner paa like mange maaneder. Ny tredje kilde:
  `UnitGUID("NPC")` + `GetPlayerInfoByGUID`. En GUID er en annen datatype og
  gaar en annen vei inn.

Faller alle fire (de tre over pluss `_autoAddTarget`), blir raden staaende som
ventende — det er riktig, vi skal ikke gjette — men **naa sier addonet fra i
chatten**. Foer var det stille, og 24.08 gikk en kveld med paa aa lete etter en
feil som ikke fantes.

### Tier telles fra AARETS sett, ikke fjoraarets

`GetTierCount` leste tooltipen etter «Set:» eller «(2/5)». Forrige sesongs tier
har noeyaktig de samme linjene — bonusen er slaatt av, men teksten staar — saa
fjoraarets brikker ble talt som aarets. Councilet kunne da se en spiller som
«ferdig utstyrt» selv om han manglet alt av gjeldende tier.

Sett-ID-en skiller dem, og den ligger paa plass 16 i `GetItemInfo`. Det er samme
felt nettsida filtrerer paa (`TIER_SETT_MIN`/`MAX` = 2000-2099 i
`lib/tier-sims.ts`), og samme sjekk NorthernSkyRaidTools gjoer.

**MAA oppdateres ved ny tier**, og de to tallene maa staa likt i addonet og paa
nettsida. Staar de ulikt, teller de to tier forskjellig — og da rangerer de
samme spiller ulikt, akkurat som i august.

### Sesjonen kan hentes tilbake etter en reload

Reloadet en raider midt i en innsamling, laa sesjonen kun i minnet og var borte
for godt. Popupen kom ikke tilbake, han svarte aldri, og offiseren maatte vente
ut hele timeren paa et svar som ikke kunne komme. Dette var den siste kjente
maaten aa falle ut av et council paa.

Klienten spoer naa `SESSION_RESUME_REQ` i det den aktiveres — noeyaktig det
oeyeblikket en gjeninnlastet klient melder seg igjen, saa det fyrer én gang og
ikke i loekke. Lederen svarer med `SESSION_RESUME`, og:

- **kun lederen svarer**, samme regel som `SESSION_START`. Ellers kunne en
  officer med hengende tilstand dyttet en gammel sesjon inn hos en som nettopp
  reloadet.
- **svaret hviskes** til den ene som spurte. Kringkastet ville det revet opp
  igjen popupen hos alle som allerede hadde svart.
- **er ingen innsamling aapen, er lederen stille.** Uten det ville hver eneste
  reload i raidet utloest en runde meldinger.
- **tida som er IGJEN foelger med**, ikke hele runden om igjen.

Meldingskoeen under comms-restriksjon husker naa kanal og mottaker. Uten det
ville en hvisket melding som ble liggende gaatt ut til HELE raidet naar
restriksjonen slapp.

### Flere items i samme handel

Trade-knappen tar hele gjelda til én person, ikke bare raden du trykket paa.
Sortert kortest handelstid foerst; taket er 6, siden siste trade-slot ikke
byttes.

Fella som ble tettet: et item som ligger i handelsvinduet staar fortsatt i
bag-sloten sin for API-et. `FindItemInBags` tar derfor imot brukte slots og
hopper over dem — uten det ville to eksemplarer av samme item lagt ETT item inn
to steder.

### Council krever officer OG raidlead

`StartMultiSession` krever naa baade `NLC.ErEkteOfficer()` og
`NLC.IsLootLeader()`. Ny `ErEkteOfficer()` er officer **uten**
gruppeleder-snarveien: `isOfficer` alene duger ikke, siden `Core.lua` gir
gruppelederen officer-tilgang, saa en raider med midlertidig lead kunne startet
councilet.

`SESSION_START` og `SESSION_CLOSE` godtas ogsaa kun fra lederen — samme felle
som `ACTIVATE` hadde til 26.08.

Merk: `rankIndex` fra `GetGuildInfo` er 0-basert. 0 = GM, 1 og 2 = de to rangene
som begge heter «Officer», 3 = Officer Alt. Blir en ekte officer nektet, sjekk
den linja foerst.

### Avstandsmaaling er fjernet helt

`UnitInRange` er borte begge steder. Det er tredje avstands-API som stenges for
addons — `CheckInteractDistance` er protected, `UnitInRange` gir secret value —
og `trade_harness` har naa en test som leser KILDEN og nekter begge navnene.
Grunnen: ingen stub skrevet i Lua kan etterligne et secret value, saa en
oppfoerselstest kan aldri fange feilen.


## 1.9.3 (2026-08-26)

### /nordlc testloot etterlot et flagg som blokkerte lederens ACTIVATE

Funnet i en gjennomgang samme dag. `testloot` satte `NLC.active` uten
`NLC.testMode`, og rydderen ser kun paa `testMode`. Et hengende `active`
BLOKKERER aktivering fra lederen — `Comms` sjekker «if not NLC.active and
fraLeder» — saa `Activate()` kjoerer aldri, `LootDetection` registreres aldri,
og klienten staar uten auto-pass og uten loot-rapport resten av kvelden. Ingen
feilmelding.

Fella laa i selve roeyktesten: `RELEASE.md` punkt 5 paalegger `/nordlc
testloot` foer hver release.

`Deactivate` nullstiller naa ogsaa `isOfficer`, som ellers ble haengende og
fikk klienten til aa aggregere `LOOT_REPORT` den ikke skulle sett.

### Tier regnes naa likt i addonet og paa nettsida

Addonet brukte sin egen flate tabell: +3 om du har 1 eller 3 brikker, +1 om du
har 0 eller 2. Den er rolle- og spec-blind, og `GetTierCount` teller forrige
tiers brikker som gjeldende.

Maalt mot ekte data 26.08 rangerte de to nesten omvendt. Mohp sto **foerst** paa
nettsida — 3 gjeldende brikker, én unna 4-set, den stoerste gevinsten som
finnes — og **nest sist** i addonet, som saa fem brikker totalt og ga ham null.

Nettsida har baade riktig spec og riktig brikketall, saa den regner ut
gevinsten og sender den i importen som `tierGain`. Addonet gjoer den om til
poeng med samme formel som nettsida: 5 % gir full pott, taket er 8.

Uten `tierGain` i importen brukes den gamle tabellen som foer, saa en klient
med utdatert import mister ikke tier-vurderingen.

**Krever ny import:** kjoer companion og `/reload`. Uten det har addonet ingen
`tierGain` og faller tilbake paa den gamle tabellen.

### RollOnLoot er pcall-et

Kallet kommer 0,05 s etter eventet, saa en utloept rull, et manuelt klikk eller
en gjenfyrt `START_LOOT_ROLL` etter reconnect ga roed Lua-feil midt i bossen —
og `lukk` kjoerte da aldri, saa rull-vinduet ble staaende. 25 ruller per boss.

## 1.9.2 (2026-08-26)

### Auto-pass i pug — kun raidlederen kan skru addonet paa

Tilbakemelding 26.08: «Vi pugga tidligere, da passa den for flere av oss.»
Ingen av dem hadde startet addonet.

Regelen har alltid vaert at lederen faar popupen og sier ja, og at resten
foelger. Chatlinja lovte det ogsaa — «Activated by raid leader.» — men
avsenderen ble aldri sjekket. Fire veier inn utenom lederen:

- `ACTIVATE` ble godtatt fra hvem som helst.
- `ACTIVATE_CHECK` ble besvart av alle som var aktive. Siden hver klient spoer
  12 ganger over 60 sekunder ved innlogging, holdt det at én i raidet hadde
  flagget hengende igjen — saa smittet det til alle med addonet.
- Roster-oppdateringer kringkastet `ACTIVATE` fra enhver *officer*, og
  `CheckOfficer` gir den rangen til alle som leder en vilkaarlig gruppe eller
  har rank <= 2 i en vilkaarlig guild.
- `SESSION_START`, `ROLL_CALL` og `VERSION_CHECK` aktiverte ogsaa, fra hvem som
  helst.

Kilden til de hengende flaggene var `/nordlc test` og `/nordlc testloot`, som
setter `active` for at utdelingsknappene skal kunne oeves solo. Flagget ble
aldri ryddet og fulgte med inn i neste raid.

Rettet:

- **All fjernaktivering krever naa at meldinga kommer fra den som leder gruppa.**
  «Vet ikke hvem lederen er» teller som nei, ikke ja.
- **Bare lederen svarer paa `ACTIVATE_CHECK`.** Svaret *er* en aktivering hos
  mottakeren, saa ingen andre har lov til aa gi det.
- **Testmodus ryddes naar du kommer i et raid.**
- **`ROLL_CALL` og `VERSION_CHECK` besvares fortsatt uansett hvem som spoer.**
  Aa svare og aa skru paa auto-passet er skilt: en installert men uaktivert
  klient maa fortsatt vaere synlig i opptellingen og for `/nordlc version`
  (Braxina-saken 19.08), men hun aktiveres ikke lenger av det.

### Manuell paaskruing stengt for alle andre enn lederen

Lederporten over stengte fjernaktiveringen, men `/nordlc activate` og
hoeyreklikk paa addon-ikonet sto fortsatt aapne for alle. Det var bare en vei
rundt porten: en raider som skrev kommandoen i en pug auto-passet paa alt.

Ingen andre enn lederen *trenger* aa aktivere. Lederen sier ja i popupen, og
resten tas av `ACTIVATE` — enten kringkastet ved neste roster-oppdatering,
eller som svar paa `ACTIVATE_CHECK`, som hver klient sender selv ved
innlogging.

- **Er du i et raid og ikke leder, sier kommandoen nei** og forklarer at du blir
  skrudd paa automatisk.
- **Utenfor raid slipper alle gjennom.** Der finnes ingen rull aa passe paa, og
  offiseren maa kunne se over importen foer folk er invitert.
- **`deactivate` er ikke gated.** Porten gaar én vei: den som ble aktivert av
  lederen maa alltid kunne skru av igjen.

Ny testrigg: `tests/manuellaktivering_harness.lua`.

Navnematchen taaler cross-realm og norske navn: realmen strippes med
`Ambiguate`, og AE, OE og AA senkes for haand. `string.lower` kan ikke brukes —
den senker byte for byte etter lokalet og gjoer «Æver» om til noe som ikke er et
navn. Ny testrigg: `tests/aktivering_harness.lua`.

Konsekvens aa vaere klar over: er council-offiseren ikke raidleder, aktiveres
ingen av seg selv. Det henger sammen med resten — auto-Need og utdelingen
forutsetter allerede at lederen er den som deler ut.

## 1.9.1 (2026-08-19)

### Diagnose (lagt til 22.08, foer release)

To linjer i diagloggen kunne ikke svare paa spoersmaal de burde kunnet svare paa.

- **«Innsamling stengt | 0 items» sier naa hvorfor.** Den samme linja betydde foer
  enten at ingenting droppet eller at filteret kastet alt — to helt ulike
  tilstander, umulige aa skille. Avviste items telles naa per grunn, og linja
  ender paa `| avvist: 14 uten handelstid`. Merk at filteret krever det aktive
  2-timers handelsvinduet, ikke bare epic-kvalitet: i gammelt innhold avvises alt,
  og det er riktig oppfoersel.
- **`ENCOUNTER_END` logges ogsaa naar addonet er av.** Registreringen laa i
  `Register()`, som kun kalles fra `Activate()`. Grenen «addon er IKKE aktiv» var
  derfor doed kode, og en hel raidkveld med addonet lastet kunne gi null linjer i
  loggen uten at noe var galt. Registreringen skjer naa ved innlasting, og
  gjentas i `Unregister()` fordi `UnregisterAllEvents()` ellers river den ned ved
  foerste `Deactivate`. `START_LOOT_ROLL` er bevisst ikke flyttet med: auto-rullen
  maa bli staaende bak `Activate()`, ellers ruller addonet Need eller Pass for deg
  i tilfeldige pug-raid.

### Hastefiks etter raidkvelden 19.08

Sesong 2s andre raidkveld. 1.9.0 fanget ingen loot og tok
interesse-popupen med seg hos alle raidere. Fem feil laa bak, alle bekreftet mot
logger fra kvelden.

### Loot-deteksjonen fanget aldri noe

- **Innsamlingsvinduet er ankret paa rullene, ikke paa killet.** Det var 12
  sekunder fra `ENCOUNTER_END`. Med Group Loot finnes itemet ikke i noens bag
  foer rullen er avgjort — paa Nek'zali 19.08 skjedde det 36 sekunder etter
  killet, altsaa 24 sekunder etter at vinduet hadde stengt. Bag-skannet fant
  derfor null hver eneste gang. Vinduet starter naa paa 45 sekunder og forlenges
  av hver `START_LOOT_ROLL` med rullens egen gjenstaaende tid, med et tak paa
  fem minutter.
- **`C_TooltipInfo.GetItemByHyperlink` finnes ikke.** Funksjonen heter
  `GetHyperlink`. Kallet var nil, saa det kastet — og siden det skjedde inne i
  bag-skannet, doede hele gjennomgangen paa det foerste itemet som ellers ville
  blitt fanget. Ett item som ikke lar seg lese koster naa det ene itemet, aldri
  resten av baggen.

### Rapporten inneholdt hele baggen

- **Kun loot fra bossen som nettopp doede rapporteres.** Bag-skannet skilte ikke
  paa hvor et item kom fra: alt tradeable med handelstid igjen ble sveipet med.
  Maalt paa The Coiled Altar 19.08 ga det 40 rapporterte items der bare 6 kom fra
  bossen — de andre 34 hadde ligget i baggen hele kvelden. Det som ligger der
  naar bossen doer holdes naa utenfor. Vil du ha restlageret, er det
  `/nordlc addall` som gjoer den jobben.
- **Taket paa innsamlingen hevet til aatte minutter.** `GetLootRollTimeLeft` ga
  270 sekunder in-game. Blir liket lootet et minutt etter killet, trengs over
  fem minutter foer rullen er avgjort — og det gamle taket paa fem stengte da
  vinduet for tidlig.

### Interesse-popupen krasjet hos alle raidere

- **Samme nil-kall traff popupen.** Et item uten equipLoc — altsaa et
  tier-token — sendte `GetAvailableCategories` inn i den samme grenen, og
  popupen doede foer foerste rad ble tegnet. Raiderne saa ingenting.
- **Popupen venter naa paa at item-data er lastet.** `C_Item.GetItemInfo` svarer
  nil for et item klienten ikke har cachet, og da ble equipLoc nil og itemet
  tolket som et token. Popupen bygges foerst naar spillet kan svare for hvert
  item, med fem sekunders frist foer den bygges likevel.

### Tier

- **Tier-tokens ble filtrert bort foer de ble sjekket.** Spillet klassifiserer et
  armor token som Miscellaneous/Junk, og «Miscellaneous» sto paa svartelista en
  linje foer token-sjekken. Hele tier-grenen var doed kode.
- **Rustningstypen leses ut av `Classes:`-linja.** Et token har underklasse
  «Junk» og ingen linje som bare sier «Plate», saa den gamle gjenkjenningen traff
  aldri. Alle klasser paa ett token deler rustningstype.
- **Alle andre enn lederen auto-passer naa ogsaa paa tokens.** Unntaket var
  skrevet som «ikke Miscellaneous» for aa spare pets og mounts, men tokens ligger
  i samme itemklasse. Rullen gikk full tid, og hvem som helst kunne Neede den.

### Fri rull paa pets, toys og mounts

- **Addonet ruller ikke paa pets, toys og mounts i det hele tatt** — heller ikke
  for raidlederen. Der ruller alle fritt, som foer. Lederen rullet Need
  automatisk paa alt, og ville dermed snappet hver eneste mount foer noen andre
  rakk aa svare. Skillet gaar paa itemets underklasse, ikke paa typenavnet, saa
  tier-tokens havner ikke lenger i samme bunke ved et uhell. Toys spoerres det om
  for seg, siden de ikke ligger i én bestemt itemklasse.

### Rangeringsvinduet kunne staa tomt

- **Klassen slaas opp med realm.** `UnitClass` godtar et spillernavn, men
  cross-realm maa realmen vaere med. Den ble strippet, oppslaget ga nil, og koden
  falt tilbake paa «Warrior» for alle. Paa et token som ikke var Plate ble hver
  eneste kandidat kastet ut. Ukjent klasse vises naa for offiseren i stedet for
  aa forsvinne.
- **Wishlist-filteret fritar tier-slots,** slik knappefilteret alltid har gjort.
  En raider kunne trykke «Upgrade» paa en tier-del og likevel bli droppet uten et
  ord.

### Raidere som har addonet, men ikke er aktivert

- **`ROLL_CALL` og `VERSION_CHECK` aktiverer naa klienten.** Begge laa bak
  aktiv-sjekken, saa en som hadde addonet installert uten aa vaere aktivert
  svarte aldri. Hun var usynlig baade i `/nordlc version` og i opptellingen ved
  council-start — og siden en uaktivert klient ikke har registrert noen events,
  auto-passet hun ikke og rapporterte ingen loot heller. Begge meldingene er
  bevis paa at en offiser holder paa, saa de aktiverer paa lik linje med at et
  council starter.
- **Enhver aktiv officer kringkaster ACTIVATE** naar rosteret endrer seg, ikke
  bare raidlederen. Er offiseren ikke leder, ble det aldri sendt, og en raider
  som logget inn eller reloadet ble staaende uaktivert uten aa vite det.

### Nytt

- **`/nordlc addall`** legger alt tradeable i baggen rett i panelet, uten
  shift-klikking. Panelet er uendret: fjern med X, og trykk Start Council.
- **`/nordlc diag`** viser hva innsamlingen faktisk gjorde — aktiv, officer,
  vindu aapnet, ruller, rapporter sendt og mottatt. Loggen overlever `/reload`.
- **Blaa skrift** paa loot som er fanget opp automatisk.
- **Blizzards rull-vinduer lukkes** etter at addonet har rullet for deg.
- **Varsel naar councilet ikke naar fram.** Svarer ingen paa roll call, sier
  addonet fra i stedet for aa la offiseren tro at alt gikk bra.

### Panelet

- **Loot Detected scroller.** Hoeyden fulgte antall items uten tak, saa tjue
  items ga et vindu hoeyere enn skjermen, uten noen maate aa naa radene nederst.

### Robusthet — én feil skal ikke ta ned et vindu

- **Radene i interesse-popupen bygges hver for seg, med vakt rundt.** Kastet én
  rad, doede hele popupen og raideren saa ingenting — det var slik tolv items ble
  til seks. Naa koster et item vi ikke klarer aa tegne det ene itemet, og du faar
  vite hvilket. Samme vakt i Loot Detected-panelet.
- **Trade-vinduet virket ikke.** `CheckInteractDistance` er protected: kallet
  blokkeres for addons og returnerer nil — og siden «not nil» er sant, sa
  avstandssjekken ALLTID «for langt unna» og nektet aa starte handelen.
  Erstattet med `UnitInRange`, som er grovere men faktisk svarer, og den advarer
  naa i stedet for aa nekte.
- **Den uferdige loot-rapporten overlever `/reload`.** Den laa kun i minnet, saa
  en reload midt i innsamlingen kastet alt. Naa lagres den, hentes ved oppstart
  og sendes — og toemmes ved sending, saa ingenting gaar dobbelt.
- **Addonet fanger sine egne feil.** `ADDON_ACTION_BLOCKED`,
  `ADDON_ACTION_FORBIDDEN` og `LUA_WARNING` logges til diagnoseloggen naar de
  gjelder oss. Det var nettopp en slik blokkering som gjorde trade-vinduet doedt
  i maanedsvis uten at noen saa det. Hver melding logges én gang.
- **Fullfoerte handler registreres riktig.** Tre feil laa i sporinga: mottakeren
  var kun kjent naar handelen ble startet fra vaart eget vindu, saa en manuell
  trade ble aldri registrert og itemet sto i «venter paa trade» for alltid; vi
  fjernet foerste oppfoering for personen uansett hva som laa i vinduet, saa gav
  du ett av tre items forsvant feil rad; og cross-realm-navn («Navn(*)») ble ikke
  gjenkjent. Mottakeren leses naa fra handelsvinduet, og innholdet fanges paa
  `TRADE_ACCEPT_UPDATE`.
- **Hvisk og «kopier navn» i wizard-menyen er guardet.** Begge kalte
  Blizzard-funksjoner ubeskyttet, midt i en klikk-sti du bruker under utdeling.

### To ting til fra en systematisk RC-gjennomgang

- **Varsel naar handelstida holder paa aa loepe ut.** Nedtellingen ble bare vist
  mens trade-vinduet sto aapent, og midt i et raid staar det lukket. Gaar de to
  timene ut, sitter itemet fast hos feil person for godt. Addonet sier naa fra
  naar noe har under tjue minutter igjen — etter kamp, ikke midt i den, og ikke
  oftere enn én gang i kvarteret.
- **Andre deteksjonsvei for loot.** `LOOT_ITEM_ROLL_WON` kommer rett fra spillet
  naar du vinner en rull, og er uavhengig av baade baggen og handelstid-lesinga.
  Fanger den opp noe bag-skannet gikk glipp av, blir det med i rapporten
  likevel. Samme item to veier gir fortsatt én oppfoering.

### Testene

- **Testdataene bruker ekte item-ID-er og inneholder et tier-token.** De gamle
  var oppdiktede ID-er der alle hadde en ekte slot. Grenen som drepte popupen i
  kveld var derfor uoppnaaelig for `/nordlc test`, `testloot` og `testpopup` —
  vi kunne kjoert dem hundre ganger uten aa se noe.

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
