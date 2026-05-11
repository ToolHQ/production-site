"""Núcleo compartilhado: checklist Panini WC 2026 e metadados das seleções."""
from __future__ import annotations

import re
from pathlib import Path

DIR = Path(__file__).resolve().parent
CHECKLIST_DEFAULT = DIR / "checklist_line.txt"

COCA_COLA = [
    (1, "Lamine Yamal", "Espanha"),
    (2, "Joshua Kimmich", "Alemanha"),
    (3, "Harry Kane", "Inglaterra"),
    (4, "Santiago Giménez", "México"),
    (5, "Antonee Robinson", "Estados Unidos"),
    (6, "Jefferson Lerma", "Colômbia"),
    (7, "Edson Álvarez", "México"),
    (8, "Virgil van Dijk", "Países Baixos"),
    (9, "Alphonso Davies", "Canadá"),
    (10, "Weston McKennie", "Estados Unidos"),
    (11, "Lautaro Martínez", "Argentina"),
    (12, "Gabriel Magalhães", "Brasil"),
]

EXTRAS = [
    ("Achraf Hakimi", "Marrocos"),
    ("Alphonso Davies", "Canadá"),
    ("Christian Pulisic", "Estados Unidos"),
    ("Cody Gakpo", "Países Baixos"),
    ("Cristiano Ronaldo", "Portugal"),
    ("Erling Haaland", "Noruega"),
    ("Federico Valverde", "Uruguai"),
    ("Florian Wirtz", "Alemanha"),
    ("Heung-min Son", "Coreia do Sul"),
    ("Jérémy Doku", "Bélgica"),
    ("Jude Bellingham", "Inglaterra"),
    ("Kylian Mbappé", "França"),
    ("Lamine Yamal", "Espanha"),
    ("Lionel Messi", "Argentina"),
    ("Luis Díaz", "Colômbia"),
    ("Luka Modrić", "Croácia"),
    ("Mohamed Salah", "Egito"),
    ("Moisés Caicedo", "Equador"),
    ("Raúl Jiménez", "México"),
    ("Vinícius Júnior", "Brasil"),
]


def parse_checklist(raw: str) -> list[tuple[str, str]]:
    raw = raw.strip()
    pat = re.compile(
        r"(?P<code>00|FWC\d+|[A-Z]{3}\d+)\s+(?P<desc>.+?)(?=\s+(?:00|FWC\d+|[A-Z]{3}\d+)\s|$)"
    )
    return [(m.group("code"), m.group("desc").strip()) for m in pat.finditer(raw)]


def normalize_sigla(code: str) -> str:
    pfx = code[:3]
    if pfx == "SWI":
        return "SUI"
    if pfx == "KAS":
        return "KSA"
    return pfx


def foil_type(desc: str) -> str:
    d = desc.strip()
    return "FOIL" if d.endswith("FOIL") else "Base"


def country_from_first_sticker(desc: str) -> str:
    if "Team Logo - " in desc:
        return desc.split("Team Logo - ", 1)[1].replace(" FOIL", "").strip()
    return ""


def load_album(checklist_path: Path | None = None):
    path = checklist_path or CHECKLIST_DEFAULT
    raw = path.read_text(encoding="utf-8")
    items = parse_checklist(raw)
    if len(items) != 980:
        raise ValueError(f"Lista base esperada: 980 figurinhas, obtido {len(items)}")
    intro = items[:9]
    museum = items[-11:]
    team_rows = items[9:-11]

    teams_meta: list[dict] = []
    for i in range(0, len(team_rows), 20):
        block = team_rows[i : i + 20]
        code0 = block[0][0]
        pfx = code0[:3]
        sigla = normalize_sigla(code0)
        country = country_from_first_sticker(block[0][1])
        group_idx = len(teams_meta) // 4
        group_letter = chr(ord("A") + group_idx)
        teams_meta.append(
            {
                "sigla_panini": pfx,
                "sigla": sigla,
                "pais": country,
                "grupo": f"Grupo {group_letter}",
                "grupo_letra": group_letter,
                "block": block,
            }
        )
    return intro, museum, teams_meta
