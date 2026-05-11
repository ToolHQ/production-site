"""
Strings e nomes de colunas por idioma para o gerador XLSX (referências estruturadas).
Gerar um ficheiro por idioma — os cabeçalhos das tabelas têm de coincidir com as fórmulas.
"""
from __future__ import annotations

import os

from dataclasses import dataclass
from typing import Literal


@dataclass(frozen=True)
class LocalePack:
    code: str
    label_human: str
    # Folhas (devem coincidir com ws.title em todo o livro)
    sh_guide: str
    sh_dashboard: str
    sh_intro: str
    sh_teams: str
    sh_museum: str
    sh_coca: str
    sh_extras: str
    sh_codes: str
    sh_groups: str
    sh_master: str
    sh_by_nation: str
    sh_packs: str
    sh_stats: str
    # Estado — valores da lista de validação (únicos, sem vírgulas)
    st_yes: str
    st_no: str
    st_trade: str
    # Cabeçalhos partilhados (tabelas)
    h_num: str
    h_code: str
    h_desc: str
    h_type: str
    h_have: str
    h_dup: str
    h_grp: str
    h_abbr: str
    h_team: str
    h_promo: str
    h_player: str
    h_origin: str
    h_notes: str
    h_section: str
    h_pct: str
    h_missing: str
    h_dup_short: str
    # Por seleção / by nation
    h_goal: str
    h_stuck: str
    h_prog: str
    h_left: str
    # Pacotes
    h_date: str
    h_packs_opened: str
    h_new_est: str
    # Siglas
    h_fifa_code: str
    h_country_name: str
    h_stickers: str
    h_obs: str
    # Grupos
    h_pick1: str
    h_pick2: str
    h_pick3: str
    h_pick4: str
    # UI copy
    guide_title: str
    guide_sub: str
    guide_map: str
    guide_section_col: str
    guide_open_col: str
    guide_legend: str
    dashboard_title: str
    dashboard_sub: str
    dashboard_tip: str
    stats_title: str
    promo_title: str
    foil_block: str
    grp_progress: str
    dup_sum: str
    chart_doughnut: str
    chart_sections: str
    chart_stickers_axis: str
    chart_groups_pct: str
    chart_pct_axis: str
    chart_have_slice: str
    chart_miss_slice: str
    # Cards dashboard (títulos — para estilo / não para match de fórmula)
    card_album: str
    card_missing: str
    card_pct: str
    card_coca: str
    card_extras: str
    card_dup: str
    card_trade: str
    card_foil: str
    card_done_teams: str
    card_today: str
    # Secções motor estatísticas (rótulos linhas)
    sec_intro: str
    sec_teams_block: str
    sec_museum: str
    sec_album_total: str
    sec_item: str
    sec_meta: str
    sec_with_yes: str
    sec_pct: str
    sec_left: str
    sec_coca: str
    sec_extras_lbl: str
    sec_foil_vs_base: str
    sec_foil: str
    sec_base: str
    grp_meta: str
    grp_have: str
    grp_pct: str
    grp_missing: str
    grp_bar: str
    grp_rank: str
    # Textos derivados nas folhas de dados
    txt_coca_origin: str
    txt_extra_note: str
    txt_panini_prefix: str
    txt_master_intro: str
    txt_master_team: str
    txt_master_museum: str


LOCALES: dict[str, LocalePack] = {
    "pt-BR": LocalePack(
        code="pt-BR",
        label_human="Português (Brasil)",
        sh_guide="Guia",
        sh_dashboard="Dashboard",
        sh_intro="Página Inicial",
        sh_teams="Seleções",
        sh_museum="Museu FIFA",
        sh_coca="Coca-Cola",
        sh_extras="Extras",
        sh_codes="Siglas",
        sh_groups="Grupos",
        sh_master="Todas (980)",
        sh_by_nation="Por seleção",
        sh_packs="Pacotes",
        sh_stats="Estatísticas",
        st_yes="Sim",
        st_no="Não",
        st_trade="Falta trocar",
        h_num="#",
        h_code="Código",
        h_desc="Descrição no álbum",
        h_type="Tipo",
        h_have="Tenho",
        h_dup="Duplicatas",
        h_grp="Grupo",
        h_abbr="Sigla",
        h_team="Seleção",
        h_promo="# Promo",
        h_player="Jogador",
        h_origin="Origem",
        h_notes="Notas",
        h_section="Secção",
        h_pct="Pct",
        h_missing="Faltam",
        h_dup_short="Dup.",
        h_goal="Meta",
        h_stuck="Coladas",
        h_prog="Progresso",
        h_left="Faltam",
        h_date="Data",
        h_packs_opened="Pacotes abertos",
        h_new_est="Figurinhas novas (estim.)",
        h_fifa_code="Sigla FIFA",
        h_country_name="Nome da seleção",
        h_stickers="Figurinhas",
        h_obs="Obs.",
        h_pick1="Seleção 1",
        h_pick2="Seleção 2",
        h_pick3="Seleção 3",
        h_pick4="Seleção 4",
        guide_title="Panini · FIFA World Cup 2026",
        guide_sub=(
            "Controlo completo da coleção — marque «Tenho», duplicatas e use o Dashboard ao vivo. "
            "Mapa do livro, progresso por seleção e registo de pacotes."
        ),
        guide_map="Mapa do livro",
        guide_section_col="Secção",
        guide_open_col="Abrir",
        guide_legend="Legenda · coluna «Tenho»",
        dashboard_title="Painel da coleção",
        dashboard_sub=(
            "Resumo dinâmico · as figurinhas base ligam-se às folhas de dados. "
            "Use o Guia para navegar."
        ),
        dashboard_tip=(
            "«Por seleção» mostra cada país com barra de progresso. "
            "«Pacotes» é apenas diário — não altera totais do álbum."
        ),
        stats_title="Panini WC 2026 · Motor analítico",
        promo_title="Promo & extras",
        foil_block="FOIL vs Base (com «Sim»)",
        grp_progress="Progresso por grupo",
        dup_sum="Soma duplicatas",
        chart_doughnut="Álbum base",
        chart_sections="Coladas por secção",
        chart_stickers_axis="Figurinhas",
        chart_groups_pct="% por grupo",
        chart_pct_axis="%",
        chart_have_slice="Coladas",
        chart_miss_slice="Faltam",
        card_album="Álbum base",
        card_missing="Faltam",
        card_pct="% Completo",
        card_coca="Coca-Cola",
        card_extras="Extras",
        card_dup="Duplicatas",
        card_trade="Falta trocar",
        card_foil="FOIL coladas",
        card_done_teams="Seleções completas",
        card_today="Hoje",
        sec_intro="Página inicial",
        sec_teams_block="Seleções (48×20)",
        sec_museum="Museu FIFA",
        sec_album_total="ÁLBUM BASE (total)",
        sec_item="Item",
        sec_meta="Meta",
        sec_with_yes="Com «Sim»",
        sec_pct="%",
        sec_left="Faltam",
        sec_coca="Coca-Cola",
        sec_extras_lbl="Extras internacionais",
        sec_foil_vs_base="FOIL vs Base (com «Sim»)",
        sec_foil="FOIL",
        sec_base="Base",
        grp_meta="Meta",
        grp_have="Com Sim",
        grp_pct="%",
        grp_missing="Faltam",
        grp_bar="Barra",
        grp_rank="Rank",
        txt_coca_origin="Rótulo Coca-Cola EUA",
        txt_extra_note="Extra internacional (sem nº no álbum)",
        txt_panini_prefix="Panini:",
        txt_master_intro="Página inicial",
        txt_master_team="Seleção",
        txt_master_museum="Museu FIFA",
    ),
    "en-US": LocalePack(
        code="en-US",
        label_human="English (US)",
        sh_guide="Guide",
        sh_dashboard="Dashboard",
        sh_intro="Intro",
        sh_teams="Teams",
        sh_museum="FIFA Museum",
        sh_coca="Coca-Cola",
        sh_extras="Extras",
        sh_codes="Codes",
        sh_groups="Groups",
        sh_master="Master (980)",
        sh_by_nation="By nation",
        sh_packs="Packs",
        sh_stats="Statistics",
        st_yes="Yes",
        st_no="No",
        st_trade="Need swap",
        h_num="#",
        h_code="Code",
        h_desc="Sticker text",
        h_type="Type",
        h_have="Got it",
        h_dup="Duplicates",
        h_grp="Group",
        h_abbr="Abbr",
        h_team="Nation",
        h_promo="#",
        h_player="Player",
        h_origin="Source",
        h_notes="Notes",
        h_section="Section",
        h_pct="Pct",
        h_missing="Missing",
        h_dup_short="Dup.",
        h_goal="Goal",
        h_stuck="Got",
        h_prog="Progress",
        h_left="Left",
        h_date="Date",
        h_packs_opened="Packs opened",
        h_new_est="New stickers (est.)",
        h_fifa_code="FIFA code",
        h_country_name="Country",
        h_stickers="Stickers",
        h_obs="Note",
        h_pick1="Team 1",
        h_pick2="Team 2",
        h_pick3="Team 3",
        h_pick4="Team 4",
        guide_title="Panini · FIFA World Cup 2026",
        guide_sub=(
            "Full sticker control — mark «Got it», duplicates, and watch the Dashboard update. "
            "Book map, per-nation progress, and a pack journal."
        ),
        guide_map="Book map",
        guide_section_col="Section",
        guide_open_col="Open",
        guide_legend="Legend · «Got it» column",
        dashboard_title="Collection overview",
        dashboard_sub=(
            "Live summary · base album pulls from Intro, Teams, and Museum sheets. "
            "Use the Guide to jump around."
        ),
        dashboard_tip=(
            "«By nation» shows each country with a progress bar. "
            "«Packs» is a personal log — it does not change album totals."
        ),
        stats_title="Panini WC 2026 · Analytics engine",
        promo_title="Promos & extras",
        foil_block="FOIL vs Base (with Yes)",
        grp_progress="Progress by group",
        dup_sum="Duplicates sum",
        chart_doughnut="Base album",
        chart_sections="Got stickers by section",
        chart_stickers_axis="Stickers",
        chart_groups_pct="% by group",
        chart_pct_axis="%",
        chart_have_slice="Collected",
        chart_miss_slice="Missing",
        card_album="Base album",
        card_missing="Missing",
        card_pct="% Done",
        card_coca="Coca-Cola",
        card_extras="Extras",
        card_dup="Duplicates",
        card_trade="Need swap",
        card_foil="FOIL collected",
        card_done_teams="Nations complete",
        card_today="Today",
        sec_intro="Intro page",
        sec_teams_block="Teams (48×20)",
        sec_museum="FIFA Museum",
        sec_album_total="BASE ALBUM (total)",
        sec_item="Item",
        sec_meta="Goal",
        sec_with_yes="With Yes",
        sec_pct="%",
        sec_left="Missing",
        sec_coca="Coca-Cola",
        sec_extras_lbl="International extras",
        sec_foil_vs_base="FOIL vs Base (with Yes)",
        sec_foil="FOIL",
        sec_base="Base",
        grp_meta="Goal",
        grp_have="Got",
        grp_pct="%",
        grp_missing="Missing",
        grp_bar="Bar",
        grp_rank="Rank",
        txt_coca_origin="Coca-Cola USA label",
        txt_extra_note="International extra (no album number)",
        txt_panini_prefix="Panini:",
        txt_master_intro="Intro page",
        txt_master_team="Team",
        txt_master_museum="FIFA Museum",
    ),
}


def normalize_lang(code: str | None) -> str:
    if not code:
        code = os.environ.get("WC2026_LANG", "pt-BR")
    x = str(code).strip().lower().replace("_", "-")
    aliases = {"pt": "pt-BR", "portuguese": "pt-BR", "en": "en-US", "english": "en-US"}
    if x in aliases:
        return aliases[x]
    if x in ("pt-br",):
        return "pt-BR"
    if x in ("en-us",):
        return "en-US"
    if x in LOCALES:
        return x
    return "pt-BR"


def get_locale(code: str | None) -> LocalePack:
    key = normalize_lang(code)
    return LOCALES[key]


def esc_formula(s: str) -> str:
    """Escapa aspas duplas dentro de strings literais em fórmulas Excel."""
    return s.replace('"', '""')


def tbl_col(tbl: str, header: str) -> str:
    """Referência estruturada a uma coluna de tabela."""
    if " " in header or "-" in header or "." in header:
        return f'{tbl}[{header}]'
    return f"{tbl}[{header}]"


LitLang = Literal["pt-BR", "en-US"]
