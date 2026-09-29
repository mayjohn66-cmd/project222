"""원정 재료/드롭 재구축 초안 생성기. 공식: 가격 = 20 x 지역배율 x 희귀도배율.
초안 파일만 만들고 프로젝트 CSV는 건드리지 않는다."""
import csv, io, collections

BASE = 20
REGION_MULT = {"forest": 1.0, "mine": 1.5, "swamp": 2.0, "ruins": 3.0}
RARITY_MULT = {"common": 1, "uncommon": 2, "rare": 4}
NODE_W = {  # 현재 expedition_map_nodes.csv 기준
    "forest": dict(battle=45, gather=25, unknown=20, treasure=10),
    "mine":   dict(battle=35, gather=40, unknown=15, treasure=10),
    "swamp":  dict(battle=50, gather=15, unknown=30, treasure=5),
    "ruins":  dict(battle=40, gather=15, unknown=25, treasure=20),
}
# (id, 이름, 희귀도, 설명)
MATS = {
 "forest": [("forest_herb","숲 약초","common","숲 바닥에서 흔히 자라는 약초다."),
            ("wild_berry","야생 열매","common","새들이 즐겨 먹는 붉은 열매다."),
            ("dry_branch","마른 가지","common","불쏘시개로 쓰기 좋은 나뭇가지다."),
            ("forest_mushroom","숲 버섯","uncommon","습한 나무 그늘에서 자란 버섯이다."),
            ("amber_sap","호박 수액","uncommon","오래된 나무에서 굳은 투명한 수액이다."),
            ("elder_seed","고목의 씨앗","rare","숲의 가장 오래된 나무에서 떨어진 씨앗이다.")],
 "mine":   [("coal","석탄","common","광산 벽에서 캐낸 검은 연료다."),
            ("stone_shard","돌 조각","common","단단한 광석 조각이다."),
            ("copper_ore","구리 광석","common","붉은빛이 도는 광석이다."),
            ("mine_crystal","수정 원석","uncommon","광산 깊은 곳에서 캐낸 수정이다."),
            ("silver_ore","은광석","uncommon","희미하게 빛나는 광석이다."),
            ("deep_gem","심층 보석","rare","광산 가장 깊은 곳에서 나온 보석이다.")],
 "swamp":  [("swamp_moss","늪 이끼","common","늪지 바위에 낀 이끼다."),
            ("marsh_reed","늪 갈대","common","질기고 길게 자란 갈대다."),
            ("bog_mud","늪 진흙","common","끈적하고 영양이 많은 진흙이다."),
            ("toxic_spore","독 포자","uncommon","다루기 위험한 포자다."),
            ("glow_algae","발광 해초","uncommon","어둠 속에서 은은하게 빛나는 해초다."),
            ("queen_jelly","여왕의 젤리","rare","늪의 여왕 슬라임에게서 얻은 젤리다.")],
 "ruins":  [("ancient_fragment","고대 파편","common","고대 유적의 깨진 조각이다."),
            ("rune_dust","룬 가루","common","룬이 새겨진 돌이 부서진 가루다."),
            ("worn_coin","낡은 동전","common","오래전 통용되던 동전이다."),
            ("rune_stone","룬석","uncommon","마력이 남아 있는 돌이다."),
            ("sealed_scroll","봉인된 두루마리","uncommon","봉인이 그대로 남은 두루마리다."),
            ("ancient_relic","고대 유물","rare","고대 문명이 남긴 귀한 유물이다.")],
}
def price(region, rar): return round(BASE * REGION_MULT[region] * RARITY_MULT[rar])

# 드롭 테이블: 상황별 (희귀도 그룹 가중치, 개수). 굴림 1번 = 아이템 1종.
def tables(region):
    m = MATS[region]; c = [x[0] for x in m if x[2]=="common"]; u = [x[0] for x in m if x[2]=="uncommon"]; r = [x[0] for x in m if x[2]=="rare"][0]
    T = {}
    T["gather"]   = [(c[0],30,1,3),(c[1],30,1,3),(c[2],30,1,3),(u[0],10,1,1)]
    T["enemy"]    = [(c[0],25,1,2),(c[1],25,1,2),(c[2],25,1,2),(u[0],12,1,1),(u[1],13,1,1)]
    T["treasure"] = [(c[0],10,2,3),(c[1],10,2,3),(c[2],10,2,3),(u[0],30,1,2),(u[1],30,1,2),(r,10,1,1)]
    T["boss"]     = [(c[0],5,3,4),(c[1],5,3,4),(c[2],5,3,4),(u[0],15,2,3),(u[1],15,2,3),(r,55,1,1)]
    return T

price_of = {i:price(rg,rar) for rg,l in MATS.items() for i,_,rar,_ in l}
def ev(table):  # 굴림 1번의 기대 판매가치 / 희귀 확률 / 기대 개수
    tw = sum(w for _,w,_,_ in table)
    val = sum(w*price_of[i]*(a+b)/2 for i,w,a,b in table)/tw
    cnt = sum(w*(a+b)/2 for _,w,a,b in table)/tw
    rare = sum(w for i,w,_,_ in table if any(i==x[0] and x[2]=="rare" for l in MATS.values() for x in l))/tw
    return val, cnt, rare

# 1) items 초안
hdr = "id,name,item_type,category,price,bag_w,bag_h,shelf_allowed,sellable,icon_path,description,attack,defense,expedition_storage,inventory_group".split(",")
buf = io.StringIO(); w = csv.writer(buf, lineterminator="\r\n"); w.writerow(hdr)
for rg,l in MATS.items():
    for i,n,rar,d in l:
        bw,bh = (2,1) if i=="ancient_relic" else (1,1)
        w.writerow([i,n,"material","material",price(rg,rar),bw,bh,"true","true",f"res://art/items/pixel_v1/{i}.png",d,0,0,"inventory","shelf"])
open("items_materials_draft.csv","w",encoding="utf-8",newline="").write(buf.getvalue())

# 2) loot 초안
buf = io.StringIO(); w = csv.writer(buf, lineterminator="\r\n"); w.writerow(["table_id","item_id","weight","min_amount","max_amount"])
for rg in MATS:
    for kind,t in tables(rg).items():
        for i,wt,a,b in t: w.writerow([f"{rg}_{kind}",i,wt,a,b])
open("expedition_loot_draft.csv","w",encoding="utf-8",newline="").write(buf.getvalue())

# 3) 한 번의 원정 시뮬레이션 지표 (일반 칸 4개 + 보스 1개)
lines = ["| 지역 | 재료 가격(흔함/드묾/매우 드묾) | 원정 1회 기대 재료 수 | 기대 판매가치 | 매우 드문 재료를 볼 확률 |","|---|---|---|---|---|"]
for rg in MATS:
    T = tables(rg); nw = NODE_W[rg]; tot = sum(nw.values())
    pb = {k:v/tot for k,v in nw.items()}
    # 미지 칸: 전투 35 / 보물 25 / 휴식 25 / 없음 15
    per = collections.defaultdict(float)
    per["enemy"] = pb["battle"] + pb["unknown"]*0.35
    per["gather"] = pb["gather"]
    per["treasure"] = pb["treasure"] + pb["unknown"]*0.25
    cnt = val = 0; p_no_rare = 1
    for k,p in per.items():
        v,c,r = ev(T[k]); val += 4*p*v; cnt += 4*p*c; p_no_rare *= (1-r*p)**4
    v,c,r = ev(T["boss"]); val += v; cnt += c; p_no_rare *= (1-r)
    ps = [price(rg,x) for x in ("common","uncommon","rare")]
    lines.append(f"| {rg} | {ps[0]}/{ps[1]}/{ps[2]} | {cnt:.1f}개 | {val:.0f}원 | {(1-p_no_rare)*100:.0f}% |")
open("run_expectation.md","w",encoding="utf-8").write("\n".join(lines)+"\n")
print("\n".join(lines))
