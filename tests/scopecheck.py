"""Finner locals som brukes over der de deklareres.

Kjoeres fra repo-rot:
    python tests/scopecheck.py

I Lua ser en funksjon bare locals som er deklarert FOER den. Kaller du en
`local function` som staar lenger nede i fila, slaas navnet opp som global, blir
nil, og kallet kaster — foerst naar den kodelinja faktisk kjoerer.

Den fella har truffet dette addonet to ganger:
  * LootDetection.lua under loot-omskrivingen (locals under Register)
  * `_vote` i Council.lua, som maatte flyttes opp for at avstemmingen skulle slaa
    inn i det hele tatt — kommentaren staar der fortsatt

Sjekken er en heuristikk, ikke en Lua-parser: den ser paa hele fila som ett
scope. Det gir ingen falske negativer for moensteret vi bryr oss om (fil-lokale
hjelpefunksjoner), og faa falske positive.
"""

import os
import re
import sys

ROT = "NordavindLC"

KOMMENTAR = re.compile(r"--\[\[.*?\]\]|--[^\n]*", re.S)
STRENG = re.compile(r'"(?:[^"\\\n]|\\.)*"' + r"|'(?:[^'\\\n]|\\.)*'")

DEKLARASJON = re.compile(r"^[ \t]*local\s+function\s+([A-Za-z_]\w*)", re.M)
# `local x = function()` og `local x` teller ogsaa naar de kalles som funksjon.
DEKLARASJON_VAR = re.compile(r"^[ \t]*local\s+([A-Za-z_]\w*)\s*=", re.M)


def linje(tekst, pos):
    return tekst.count("\n", 0, pos) + 1


def sjekk(sti):
    raa = open(sti, encoding="utf-8", errors="replace").read()
    tekst = STRENG.sub('""', KOMMENTAR.sub(" ", raa))

    deklarert = {}
    for m in DEKLARASJON.finditer(tekst):
        deklarert.setdefault(m.group(1), linje(tekst, m.start()))
    for m in DEKLARASJON_VAR.finditer(tekst):
        deklarert.setdefault(m.group(1), linje(tekst, m.start()))

    funn = []
    for navn, dek_linje in deklarert.items():
        for m in re.finditer(r"(?<![\w.:])" + re.escape(navn) + r"\s*\(", tekst):
            bruk = linje(tekst, m.start())
            if bruk < dek_linje:
                funn.append((navn, bruk, dek_linje))
    return funn


def main():
    if not os.path.isdir(ROT):
        print("Kjoer fra repo-rot (fant ikke %s/)" % ROT)
        return 2

    totalt = 0
    for dirpath, _, filnavn in os.walk(ROT):
        if "Libs" in dirpath:
            continue
        for fn in sorted(filnavn):
            if not fn.endswith(".lua"):
                continue
            sti = os.path.join(dirpath, fn)
            for navn, bruk, dek in sorted(sjekk(sti), key=lambda x: x[1]):
                print("  %s:%d bruker «%s», deklarert foerst paa linje %d"
                      % (sti, bruk, navn, dek))
                totalt += 1

    if totalt == 0:
        print("Ingen locals brukt over deklarasjonen.")
        return 0
    print()
    print("%d treff. Hver av dem slaar opp en global og blir nil naar linja kjoerer." % totalt)
    return 1


if __name__ == "__main__":
    sys.exit(main())
