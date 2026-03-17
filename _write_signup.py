#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Write gamejam_signup_page.gd with proper UTF-8 encoding."""
import os

content = r'''extends MarginContainer
## AGJ 2025 新星赛道报名页 — 预制场景页面

const AIServiceClass = preload("res://scripts/llm/AIService.gd")

# ── 配色 ──────────────────────────────────────────────
const C_PAGE_BG      := Color("#080B12")
const C_NAV_BG       := Color("#060810")
const C_HERO_BG      := Color("#0A0D18")
const C_CARD_BG      := Color("#0D1020")
const C_CARD_BORDER  := Color("#1A1F35")

const C_ACCENT       := Color("#3D6FFF")
const C_ACCENT_DIM   := Color("#1E3A8A")
const C_ORANGE       := Color("#E8622A")
const C_ORANGE_DIM   := Color("#7A3010")

const C_WHITE        := Color("#ECEEF8")
const C_DIM          := Color("#7A82A0")
const C_MUTED        := Color("#3D4460")
const C_ACCENT_TEXT  := Color("#5B8AFF")

const C_FIELD_BG     := Color("#0A0D1A")
const C_FIELD_BORDER := Color("#1A1F35")
const C_FIELD_FOCUS  := Color("#3D6FFF")
const C_FIELD_TEXT   := Color("#D8DCF0")
const C_FIELD_PH     := Color("#3D4460")

const C_ERROR        := Color("#E84040")
const C_ERROR_BG     := Color("#180A0A")
const C_SUCCESS      := Color("#28C76F")
const C_SUCCESS_BG   := Color("#0A1810")
const C_INFO_BG      := Color("#0A0D1A")

const C_RULE         := Color("#141828")

# ── 数据 ──────────────────────────────────────────────
const UNIVERSITY_NAME: String = "蓝鲸大学"
const COLLEGE_OPTIONS: PackedStringArray = [
	"互动媒体学院", "计算机学院", "艺术与设计学院",
	"文学与新闻学院", "外国语学院", "心理学院", "商学院",
]
'''

# Write first part
path = os.path.join("scripts", "apps", "browser", "pages", "gamejam_signup_page.gd")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(content)

print(f"Written {len(content)} chars to {path}")
