class_name ManagementTabs
extends RefCounted
## 관리 책의 탭 종류. 각 탭 화면이 ManagementMenu 자체를 알지 않고도 쓸 수 있도록 따로 둔다.
## ManagementMenu.MenuTab / InfoTab 은 이 값을 가리키는 별칭이라 기존 코드도 그대로 동작한다.

enum MenuTab {
	INVENTORY,
	PRODUCTION,
	EMPLOYEE,
	BLUEPRINT,
	CONSTRUCTION,
	SCHEDULE,
	HISTORY,
	REQUESTS
}

enum InfoTab {
	BASIC,
	DETAIL,
	TREND,
	RECORD,
	MILESTONES
}
