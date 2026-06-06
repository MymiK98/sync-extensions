#!/usr/bin/env python3
"""sync-extensions catalog — single index over every available skill.

Sources merged:
  - plugins        : skill/manifest.json -> plugins[]   (marketplace plugins)
  - standalone     : skill/manifest.json -> standalone_skills.repos[].skills[]
  - local          : library/<id>/SKILL.md              (personal warehouse)

Modes:
  catalog.py list            human table (id | type | installed | source)
  catalog.py json            full catalog as JSON
  catalog.py get <id>        shell-eval lines for one item (TYPE=, REPO=, ...)
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR", os.path.join(HOME, ".claude"))

MANIFEST = os.path.join(HERE, "skill", "manifest.json")
LIBRARY  = os.path.join(HERE, "library")
SKILLS_DIR = os.path.join(CLAUDE, "skills")
INSTALLED  = os.path.join(CLAUDE, "plugins", "installed_plugins.json")
KNOWN      = os.path.join(CLAUDE, "plugins", "known_marketplaces.json")
LOCK       = os.path.join(HOME, ".agents", ".skill-lock.json")


def _load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def _desc(skill_md):
    """Pull the description: line from a SKILL.md frontmatter."""
    try:
        with open(skill_md) as f:
            txt = f.read(4000)
        m = re.search(r"^description:\s*(.+)$", txt, re.MULTILINE)
        if m:
            d = m.group(1).strip().strip('"').strip("'")
            return (d[:90] + "…") if len(d) > 91 else d
    except Exception:
        pass
    return ""


def build():
    man = _load(MANIFEST, {})
    installed = _load(INSTALLED, {}).get("plugins", {})
    known = _load(KNOWN, {})
    lock = _load(LOCK, {}).get("skills", {})
    items = []

    # marketplace plugins
    mkt_repo = {m["name"]: m["repo"] for m in man.get("marketplaces", [])}
    for p in man.get("plugins", []):
        key = f'{p["name"]}@{p["marketplace"]}'
        items.append({
            "id": p["name"],
            "type": "plugin",
            "plugin": key,
            "marketplace": p["marketplace"],
            "marketplace_repo": mkt_repo.get(p["marketplace"], ""),
            "provides": p.get("provides", p["name"]),
            "installed": key in installed,
            "mkt_known": p["marketplace"] in known,
            "source": mkt_repo.get(p["marketplace"], p["marketplace"]),
            "desc": p.get("provides", ""),
        })

    # standalone skills (vercel skills CLI)
    for r in man.get("standalone_skills", {}).get("repos", []):
        for s in r.get("skills", []):
            seed = os.path.join(HERE, "agents-seed", "skills", s, "SKILL.md")
            items.append({
                "id": s,
                "type": "standalone",
                "repo": r["repo"],
                "installed": s in lock or os.path.lexists(os.path.join(SKILLS_DIR, s)),
                "source": r["repo"],
                "desc": _desc(seed),
            })

    # local warehouse skills
    if os.path.isdir(LIBRARY):
        for name in sorted(os.listdir(LIBRARY)):
            d = os.path.join(LIBRARY, name)
            md = os.path.join(d, "SKILL.md")
            if os.path.isdir(d) and os.path.isfile(md):
                link = os.path.join(SKILLS_DIR, name)
                items.append({
                    "id": name,
                    "type": "local",
                    "path": os.path.relpath(d, HERE),
                    "installed": os.path.lexists(link),
                    "source": "library/",
                    "desc": _desc(md),
                })
    return items


def cmd_list(items):
    if not items:
        print("catalog empty.")
        return
    w = max(len(i["id"]) for i in items)
    print(f'{"":2}{"ID".ljust(w)}  {"TYPE".ljust(10)}  {"USE":3}  SOURCE / DESC')
    print("  " + "-" * (w + 40))
    for i in items:
        mark = "\033[32m●\033[0m" if i["installed"] else "\033[90m○\033[0m"
        desc = i.get("desc") or i.get("source", "")
        print(f'  {mark} {i["id"].ljust(w)}  {i["type"].ljust(10)}  '
              f'{"on " if i["installed"] else "off"}  {desc}')
    on = sum(1 for i in items if i["installed"])
    print(f'\n  {on}/{len(items)} installed  (● on / ○ off)')


def cmd_get(items, wanted):
    for i in items:
        if i["id"] == wanted:
            def e(k):
                v = i.get(k, "")
                return str(v).replace('"', '\\"')
            print(f'TYPE="{e("type")}"')
            print(f'PLUGIN="{e("plugin")}"')
            print(f'MARKETPLACE="{e("marketplace")}"')
            print(f'MARKETPLACE_REPO="{e("marketplace_repo")}"')
            print(f'REPO="{e("repo")}"')
            print(f'LIBPATH="{e("path")}"')
            print(f'INSTALLED="{1 if i["installed"] else 0}"')
            return 0
    print(f'# id not found: {wanted}', file=sys.stderr)
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
