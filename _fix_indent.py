#!/usr/bin/env python3
"""Fix indentation for login_screen.gd"""
import re

path = r"e:\GodotProjects\godot-ai-streamer-main\scripts\pseudo_os\login_screen.gd"

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

lines = content.split("\n")
result = []
indent_level = 0
prev_ends_colon = False

for line in lines:
    stripped = line.strip()

    # Empty line
    if not stripped:
        result.append("")
        prev_ends_colon = False
        continue

    # Top-level declarations (no indent)
    is_top_level = False
    for prefix in ("class_name ", "##", "signal ", "const ", "@onready ", "@export "):
        if stripped.startswith(prefix):
            is_top_level = True
            break
    # var at indent 0 (class-level)
    if stripped.startswith("var ") and indent_level == 0:
        is_top_level = True

    if stripped.startswith("func "):
        indent_level = 0
        result.append(stripped)
        indent_level = 1
        prev_ends_colon = False
        continue

    if is_top_level:
        indent_level = 0
        result.append(stripped)
        prev_ends_colon = False
        continue

    # Already has tabs? keep as is
    if line.startswith("\t"):
        result.append(line)
        # update indent level from actual tabs
        indent_level = len(line) - len(line.lstrip("\t"))
        if stripped.endswith(":") and not stripped.startswith("#"):
            indent_level += 1
        prev_ends_colon = False
        continue

    # Need to add indent
    # Check if previous line ended with colon (increase indent)
    if prev_ends_colon:
        indent_level += 1

    # Dedent keywords
    if stripped in ("else:", "elif ") or stripped.startswith("else:") or stripped.startswith("elif "):
        indent_level = max(indent_level - 1, 1)

    # Closing paren lines like ")" 
    if stripped == ")":
        indent_level = max(indent_level - 1, 1)

    result.append("\t" * indent_level + stripped)

    # Track if this line ends with colon for next indent
    # But not comments, strings, etc
    clean = stripped
    if "#" in clean:
        clean = clean[:clean.index("#")].strip()
    prev_ends_colon = clean.endswith(":") and not clean.startswith("#")
    
    # Dedent after return/continue/break/pass
    if stripped in ("return", "pass", "break", "continue") or stripped.startswith("return "):
        indent_level = max(indent_level - 1, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(result))

print(f"Fixed {len(result)} lines")
