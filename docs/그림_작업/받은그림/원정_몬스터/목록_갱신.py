from pathlib import Path
import csv, json

GROUPS = [("", [64,64], [32,56]), ("일반_추가", [64,64], [32,56]), ("보스", [128,128], [64,112])]

def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def known_ids(folder, current=()):
    ids = set(current)
    for sub, _, _ in GROUPS:
        path = folder/sub/"후보_목록.json"
        if path.is_file(): ids.update(a["id"] for a in read(path)["assets"])
    return ids

def refresh_catalog(folder):
    root = folder.parents[3]
    with (root/"data/expedition/enemies.csv").open(encoding="utf-8-sig", newline="") as f:
        enemies = list(csv.DictReader(f))
    combined = []
    manifests = []
    for sub, canvas, anchor in GROUPS:
        p = folder/sub/"후보_목록.json"
        if not p.is_file(): continue
        m = read(p); manifests.append((p,m))
        for a in m["assets"]:
            entry = dict(a, canvas=canvas, anchor=anchor, boss=sub=="보스")
            if sub:
                for key in ["sprite","source"]: entry[key] = sub+"/"+entry[key]
            combined.append(entry)
    ids = {a["id"] for a in combined}
    assert len(ids)==len(combined), "중복 몬스터 ID"
    assert ids <= {e["id"] for e in enemies}, "데이터에 없는 몬스터"
    remaining = [dict(id=e["id"],name=e["name"],boss=e["loot_table"].endswith("_boss"),status="not_generated") for e in enemies if e["id"] not in ids]
    coverage = dict(enemy_ids=len(enemies),generated_ids=len(ids),remaining_ids=len(remaining),ordinary_remaining=sum(not e["boss"] for e in remaining),boss_remaining=sum(e["boss"] for e in remaining))
    def save(p,d): p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for p,m in manifests:
        m["coverage"] = coverage; save(p,m)
        save(p.parent/"미제작_목록.json",dict(source="data/expedition/enemies.csv",remaining=remaining))
    save(folder/"미제작_목록.json",dict(source="data/expedition/enemies.csv",remaining=remaining))
    save(folder/"전체_후보_목록.json",dict(status="candidate_not_installed",runtime_applied=False,animation=False,anchors_provisional=True,canvas_by_group={s or "기본":c for s,c,_ in GROUPS},coverage=coverage,assets=combined))
    return coverage
