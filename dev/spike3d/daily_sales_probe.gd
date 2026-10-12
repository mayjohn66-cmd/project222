extends Node
## 하루 판매량(수요) 어림 측정. 가게를 열어 두고 시간대별 도착률 → 손님 유형 → 원하는 품목을 뽑는 계산만 반복한다.
## (ShopOfflineSimulator 와 같은 함수를 쓴다. 진열대·직원·캐릭터는 만들지 않는다.)
## 사용: godot --headless --path . res://dev/spike3d/daily_sales_probe.tscn -- [시뮬레이션 일수 기본 300] [재고품목 쉼표구분 기본 bread,water]
## 보는 것: 하루 도착 손님 수(시간대별), 품목별 하루 수요량(개), 재고가 있을 때 하루 판매액 상한.
## 한계: 무작위라 일수가 적으면 흔들린다. 플레이어가 영업 시간을 정하므로 24시간 열었을 때와 낮(8~20시)만 연 경우를 둘 다 낸다.

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var days: int = int(args[0]) if args.size() > 0 else 300
	var stocked: Array = (args[1] if args.size() > 1 else "bread,water").split(",")
	GameState.initialize_new_game()
	var stocked_ids: Array[String] = []
	for s in stocked: stocked_ids.append(str(s))
	var arrivals_by_hour := PackedFloat32Array()
	arrivals_by_hour.resize(24)
	var demand := {}        # item_id -> 개수 합
	var demand_day := {}    # item_id -> 개수 합(낮 8~20시)
	var customers_total := 0
	var customers_day := 0
	var empty_requests := 0
	for d in range(days):
		var carry := 0.0
		for hour in range(24):
			carry += CustomerArrivalData.get_rate(hour)
			var n: int = int(floor(carry))
			carry -= float(n)
			arrivals_by_hour[hour] += n
			for _i in range(n):
				customers_total += 1
				var is_day := hour >= 8 and hour < 20
				if is_day: customers_day += 1
				var type_data: Dictionary = CustomerTypeData.get_random_customer_type(1 + d, {}, EmployeeData.get_period_at_hour(hour))
				var type_id := str(type_data.get("customer_type_id", ""))
				if type_id.is_empty(): type_id = "villager"
				var req: Dictionary = CustomerDemandData.get_random_wanted_request(type_id, 1 + d, stocked_ids)
				var item_id := str(req.get("item_id", ""))
				if item_id.is_empty():
					empty_requests += 1
					continue
				var amount: int = maxi(int(req.get("amount", 1)), 1)
				demand[item_id] = int(demand.get(item_id, 0)) + amount
				if is_day: demand_day[item_id] = int(demand_day.get(item_id, 0)) + amount
	print("시뮬레이션 %d일 · 진열 재고 품목: %s" % [days, ",".join(stocked)])
	print("하루 도착 손님: 24시간 %.1f명 · 낮(8~20시) %.1f명" % [float(customers_total) / days, float(customers_day) / days])
	var line := "시간대별 하루 평균 도착: "
	for h in range(24): line += "%d시 %.1f / " % [h, arrivals_by_hour[h] / days]
	print(line)
	print("원하는 품목이 비어 돌아간 손님(하루): %.2f명" % (float(empty_requests) / days))
	var keys: Array = demand.keys()
	keys.sort_custom(func(a, b): return demand[a] > demand[b])
	print("품목별 하루 수요(개) — 24시간 / 낮만 / 가격")
	var stocked_value := 0.0
	for k in keys.slice(0, 15):
		var price: int = ItemData.get_item_price(str(k))
		print("  %-26s %6.2f / %6.2f / %dG" % [str(k), float(demand[k]) / days, float(demand_day.get(k, 0)) / days, price])
		if stocked.has(str(k)): stocked_value += float(demand[k]) / days * price
	print("진열 품목(%s)의 하루 수요 금액 합: %.0fG" % [",".join(stocked), stocked_value])
	get_tree().quit()
