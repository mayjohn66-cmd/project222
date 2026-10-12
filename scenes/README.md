# scenes/ — 씬 (53개)

```
scenes/
├─ shop/        # 가게(30): main.tscn(전체 조립) · store_floor · store_actors · customer_spawner
│  ├─ requests/   #   이야기 구조·조건 default_*.tres 27개(대사는 data/shop/requests/requests_text.csv)
│  ├─ tutorial/ blacksmith/ employees/ events/ power/ preservation/ production/ warehouse/ …   # 기능별 씬·설정
│  └─ actors/ objects/ ui/ world/
├─ shared/ui/   # 여러 화면이 같이 쓰는 UI 조각(13)
├─ expedition/  # 원정(9)
└─ core/title/  # 타이틀 화면(1)
```
이야기의 조건·순서는 `scenes/shop/requests/default_*.tres`에, 대사는 CSV에 있다.
