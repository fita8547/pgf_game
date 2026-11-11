# RPS 게임 에셋 (GLB)

단위 m · Y-up · 캐릭터 정면 +Z · 총구 -Z

## 폴더
- `glb/characters` 전신 캐릭터 12명. 관절 피벗 계층 + `lobby_idle` 애니메이션 (대기창용). `hand_R/weapon_socket_R`에 아무 총이나 붙이면 들고 있는 자세가 됨.
- `glb/fp_arms` 캐릭터별 1인칭 팔. 루트 노드 `arm_R`, `arm_L`.
- `glb/fp_rigs` 총별 1인칭 리그 + 애니메이션 `idle`, `fire`, `reload`, `draw`. 노드 `weapon`, `grip_R`, `grip_L`, `ads_sight`.
- `glb/guns` 총기 단독 모델 7종 (원점 = 손잡이).
- `glb/skills/<캐릭터>/` 스킬 48개 (원점 = 바닥 중앙, 투사체는 +Z).
- `glb/maps` 맵 5개: rps_arena (3라인), desert_ruins (사막 유적), frost_harbor (설원 항구), neon_rooftops (네온 옥상), jungle_temple (정글 사원). 모두 A팀 z+ / B팀 z- 대칭, 최상위 그룹 노드로 구역이 나뉨.
- `glb/fx` 사망 이펙트 (death_cat, death_dog: `death` 애니메이션 2.6초)와 킬 배지 (kill_paw, kill_headshot: `pop` 애니메이션 1.2초). 킬 배지는 카메라 자식으로 화면 하단 중앙에 작게 띄우면 됨.
- `catalog.json` 캐릭터 역할 (디펜서/어택/힐러/컨트롤러)·스킬 설명·쿨타임·총별 조준 수치·맵 1인칭 카메라 위치.

## 1인칭 조합 (12 × 7)
1. 카메라 자식으로 `fp_rigs/<총>.glb` 로드
2. `fp_arms/<캐릭터>.glb`의 `arm_R` → `grip_R`, `arm_L` → `grip_L` 자식으로 이동 (로컬 위치 0)
3. 리그의 애니메이션 클립 재생 (`fire`, `reload` 등은 1회 재생 후 `idle`로 복귀)

## 정조준(줌)
`catalog.json`의 `guns[].ads`
- `hold`: 기본 들고 있는 위치, `sight`: 총 로컬 조준점(`ads_sight` 노드와 같음), `eye`: 눈과 조준점 거리
- 조준 시 뷰모델 오프셋 = `(0,0,-eye) - (hold + sight)`, 카메라 FOV 70 → `ads_fov`
- `overlay: true`(저격소총)는 줌 완료 시 스코프 화면으로 전환하고 뷰모델 숨김

## 다시 생성
`python3 src/build.py` (numpy, scipy 필요). 모양 수정은 `guns_hq.py`, `chars_hq.py`, `fp.py`, `map_arena.py`, `maps_more.py`, `fx.py`, 스킬은 `build_all.py`.
