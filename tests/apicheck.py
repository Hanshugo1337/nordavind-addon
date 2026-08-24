"""Finner WoW-API-navn vi er alene om aa bruke.

Kjoeres fra repo-rot:
    python tests/apicheck.py

Bakgrunnen: 2026-08-19 gikk 1.9.0 ut med `C_TooltipInfo.GetItemByHyperlink`.
Det navnet finnes ikke — funksjonen heter `GetHyperlink`. Kallet var nil, saa det
kastet, og siden det laa inne i bag-skannet og i interesse-popupen tok det med
seg baade loot-deteksjonen og raidernes vindu. Hele guilden fikk det.

Feilen var triviell aa oppdage utenfra: NordavindLC var det ENESTE addonet i
AddOns-mappa som brukte navnet, mens tretten andre brukte `GetHyperlink`. Denne
sjekken gjoer nettopp den sammenligningen — vaare API-kall mot alt annet som
faktisk kjoerer i klienten.

Et treff er ikke bevis paa feil. Det betyr «ingen andre bruker dette», og det er
verdt et blikk foer en release gaar ut til tjueaatte mennesker.
"""

import os
import re
import sys

ADDONS = r"C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
OSS = "NordavindLC"

# C_Namespace.Funksjon — den formen feilen hadde, og der de fleste nye API-ene bor.
KALL = re.compile(r"\b(C_[A-Za-z0-9_]+\.[A-Za-z0-9_]+)\b")

# Globale WoW-funksjoner: StorBokstav... etterfulgt av «(». Samme klasse feil kan
# gjemme seg der — GroupLootContainer_RemoveFrame, RunNextFrame, RollOnLoot.
GLOBALT = re.compile(r"(?<![\w.:])([A-Z][A-Za-z0-9_]{3,})\s*\(")

# Ace/LibStub er biblioteker, ikke WoW-API.
BIBLIOTEK = re.compile(r"^(LibStub|AceComm|AceSerializer|LibDeflate|CallbackHandler)")

# Kommentarer og strenger maa vekk foer vi leter. Uten det treffer moensteret paa
# «ENCOUNTER_END», «Disenchant» og halve kommentarteksten.
KOMMENTAR = re.compile(r"--\[\[.*?\]\]|--[^\n]*", re.S)
STRENG = re.compile(r'"(?:[^"\\\n]|\\.)*"' + r"|'(?:[^'\\\n]|\\.)*'")
DEFINERT = re.compile(r"function\s+(?:[\w.:]*[.:])?([A-Za-z_]\w*)\s*\(")

IGNORER_FIL = ("Libs" + os.sep,)


def les(sti):
    try:
        with open(sti, encoding="utf-8", errors="replace") as f:
            tekst = f.read()
    except OSError:
        return ""
    tekst = KOMMENTAR.sub(" ", tekst)
    return STRENG.sub('""', tekst)


def lua_filer(rot, hopp_over_libs):
    for dirpath, _, filnavn in os.walk(rot):
        if hopp_over_libs and any(d in dirpath for d in IGNORER_FIL):
            continue
        for fn in filnavn:
            if fn.endswith(".lua"):
                yield os.path.join(dirpath, fn)


def egne_navn(rot):
    """Funksjoner vi definerer selv. De er ikke WoW-API."""
    navn = set()
    for sti in lua_filer(rot, hopp_over_libs=True):
        for m in DEFINERT.finditer(les(sti)):
            navn.add(m.group(1))
    return navn


def samle(rot, hopp_over_libs=True):
    funnet = {}
    for sti in lua_filer(rot, hopp_over_libs):
        tekst = les(sti)
        for m in KALL.finditer(tekst):
            funnet.setdefault(m.group(1), []).append(sti)
        for m in GLOBALT.finditer(tekst):
            navn = m.group(1)
            if not BIBLIOTEK.match(navn):
                funnet.setdefault(navn, []).append(sti)
    return funnet


def main():
    vaart_rot = os.path.join(os.getcwd(), OSS)
    if not os.path.isdir(vaart_rot):
        print("Kjoer fra repo-rot (fant ikke %s/)" % OSS)
        return 2
    if not os.path.isdir(ADDONS):
        print("Fant ikke AddOns-mappa — hopper over sammenligningen.")
        return 0

    vaare = samle(vaart_rot)
    for n in egne_navn(vaart_rot):
        vaare.pop(n, None)

    andre = {}
    for navn in sorted(os.listdir(ADDONS)):
        if navn == OSS:
            continue
        sti = os.path.join(ADDONS, navn)
        if not os.path.isdir(sti):
            continue
        for api in samle(sti, hopp_over_libs=False):
            andre.setdefault(api, set()).add(navn)

    alene = {api: filer for api, filer in vaare.items() if api not in andre}

    print("API-kall i %s: %d unike" % (OSS, len(vaare)))
    print("Sammenlignet mot %d unike navn i resten av AddOns-mappa" % len(andre))
    print("-" * 70)

    if not alene:
        print("Ingen API-navn vi er alene om.")
        return 0

    print("%d navn INGEN andre addons bruker:" % len(alene))
    print()
    for api in sorted(alene):
        filer = sorted({os.path.relpath(f, os.getcwd()) for f in alene[api]})
        print("  %s" % api)
        for f in filer:
            print("      %s" % f)
        if "." in api:
            rom = api.split(".")[0]
            naboer = sorted(a.split(".")[1] for a in andre if a.startswith(rom + "."))
            if naboer:
                print("      andre bruker i %s: %s" % (rom, ", ".join(naboer)))
        print()

    print("Et treff er ikke bevis paa feil — men sjekk hvert av dem foer release.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
