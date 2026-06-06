#!/usr/bin/env python3
"""Warehouse catalog — lists MY skills stored in this repo (skills/*).

Each skill is a folder skills/<id>/ with a SKILL.md. A skill is "installed"
when it is symlinked (or copied) into ~/.claude/skills/<id>.

External plugins that a skill installs (e.g. sync-extensions' caveman,
superpowers) are NOT listed here — they are that skill's own payload.

Modes:
  catalog.py list          human table (id | installed | description)
  catalog.py json          full catalog as JSON
  catalog.py get <id>      shell-eval lines for one skill (PATH=, INSTALLED=)
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude"))
WAREHOUSE = os.path.join(HERE, "skills")
SKILLS_DIR = os.path.join(CLAUDE, "skills")


def _desc(skill_md):
    try:
        with open(skill_md) as f:
            txt = f.read(4000)
        m = re.search(r"^description:\s*(.+)$", txt, re.MULTILINE)
        if m:
            d = m.group(1).strip().strip('"').strip("'")
            return (d[:100] + "…") if len(d) > 101 else d
    except Exception:
        pass
    return ""


def build():
    items = []
    if os.path.isdir(WAREHOUSE):
        for name in sorted(os.listdir(WAREHOUSE)):
            d = os.path.join(WAREHOUSE, name)
            md = os.path.join(d, "SKILL.md")
            if os.path.isdir(d) and os.path.isfile(md):
                link = os.path.join(SKILLS_DIR, name)
                items.append({
                    "id": name,
                    "path": os.path.relpath(d, HERE),
                    "installed": os.path.lexists(link),
                    "linked_here": os.path.islink(link) and os.path.realpath(link) == os.path.realpath(d),
                    "desc": _desc(md),
                })
    return items


def cmd_list(items):
    if not items:
        print("warehouse empty — add a skill under skills/<name>/SKILL.md")
        return
    w = max(len(i["id"]) for i in items)
    print(f'  {"":2}{"SKILL".ljust(w)}  {"USE":3}  DESCRIPTION')
    print("  " + "-" * (w + 50))
    for i in items:
        mark = "\033[32m●\033[0m" if i["installed"] else "\033[90m○\033[0m"
        print(f'  {mark} {i["id"].ljust(w)}  {"on " if i["installed"] else "off"}  {i["desc"]}')
    on = sum(1 for i in items if i["installed"])
    print(f'\n  {on}/{len(items)} installed  (● on / ○ off)')


def cmd_get(items, wanted):
    for i in items:
        if i["id"] == wanted:
            print(f'SKILLPATH="{i["path"]}"')
            print(f'INSTALLED="{1 if i["installed"] else 0}"')
            print(f'LINKED_HERE="{1 if i["linked_here"] else 0}"')
            return 0
    print(f'# skill not found: {wanted}', file=sys.stderr)
    return 1


def main():
    items = build()
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    if mode == "json":
        print(json.dumps(items, indent=2))
    elif mode == "get":
        sys.exit(cmd_get(items, sys.argv[2]) if len(sys.argv) > 2 else 2)
    else:
        cmd_list(items)


if __name__ == "__main__":
    main()
