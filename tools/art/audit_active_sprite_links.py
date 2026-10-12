"""Read-only audit of active drawing paths, gathering selection, wall and furniture icons."""
from pathlib import Path
import csv
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]


def read_json(path):
    return json.loads((ROOT/path).read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    checks = 0
    failures = []
    def check(ok, label):
        nonlocal checks
        checks += 1
        if not ok:
            failures.append(label)
    def paths(value):
        nonlocal checks
        if isinstance(value, dict):
            if isinstance(value.get("path"), str) and value["path"].startswith("res://"):
                path = ROOT/value["path"][6:]
                check(path.is_file(), "Missing active drawing: "+value["path"])
                if path.is_file() and value.get("sha256"):
                    check(sha(path) == value["sha256"], "Changed selected pixels: "+value["path"])
            for v in value.values():
                paths(v)
        elif isinstance(value, list):
            for v in value:
                paths(v)
    for file in sorted((ROOT/"data/art").glob("*assets.json")):
        paths(json.loads(file.read_text(encoding="utf-8")))
    sprites = read_json("data/art/expedition_sprite_assets.json")["assets"]
    selection = {}
    for row in sprites:
        if row["group"] != "objects":
            continue
        for table in [row.get("table")] + row.get("table_aliases", []):
            if not table:
                continue
            check(table not in selection, "Ambiguous gather picture: "+table)
            selection[table] = row["id"]
    encounters = {}
    for line in (ROOT/"scenes/expedition/rooms/default_content_settings.tres").read_text(encoding="utf-8").splitlines():
        if '"sites"' in line:
            entry = json.loads(line.rstrip(","))
            encounters[entry["id"]] = entry["sites"]
    for sites in encounters.values():
        for site in sites:
            check(site["table"] in selection, "Unmapped gathering site: "+site["table"])
    with (ROOT/"data/expedition/expedition_events.csv").open(encoding="utf-8-sig", newline="") as f:
        events = list(csv.DictReader(f))
    active_tables = set()
    for event in events:
        if event["node_type"] != "gather" or event["result_type"] != "loot":
            continue
        tables = [s["table"] for s in encounters.get(event["event_id"], [])] or [event["target_id"]]
        for table in tables:
            active_tables.add(table)
            check(table in selection, "Unmapped active event: "+event["event_id"]+" / "+table)
    with (ROOT/"data/shop/catalogs/furniture_items.csv").open(encoding="utf-8-sig", newline="") as f:
        furniture = list(csv.DictReader(f))
    for row in furniture:
        path = row["icon_path"]
        check(bool(path) and (ROOT/path.removeprefix("res://")).is_file(), "Missing furniture menu image: "+row["id"])
    wall = next(r for r in read_json("data/art/village_sprite_assets.json")["assets"] if r["id"] == "low_wall")
    check(wall.get("repeat_module") is True, "Stone wall isn't connected to repeat renderer")
    check(wall["path"] == "res://art/received/village/stone_wall.png", "Wrong stone wall selection")
    check(all(0 <= p[0] <= 64 and 0 <= p[1] <= 96 for p in wall["footprint"]),
          "Wall module footprint uses coordinates from the former large image")
    check(sha(ROOT/wall["path"][6:]) == sha(ROOT/"docs/그림_작업/받은그림/돌담_모듈/stone_wall.png"),
          "Connected stone wall differs from the selected one")
    result = dict(checks=checks, failures=failures, active_gather_tables=sorted(active_tables),
                  furniture_icons=len(furniture), expedition_sprites=len(sprites),
                  scope="Current manifests and actual gather events; unused concepts and animations excluded")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
