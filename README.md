# RPS — 1인칭 팀 대전 히어로 슈터

Flutter Web(UI) + three.js(3D) 클라이언트, Dart 서버, 공용 Dart 게임 로직으로 만든 5대5 점령전 슈터.
캐릭터 12명(역할 4종), 스킬 48개, 총 7종, 맵 5개.

## 폴더
| 폴더 | 내용 |
|---|---|
| `shared/` | 공용 게임 로직 `rps_shared` (콘텐츠 표, GLB→충돌, 이동·사격·스킬·점령전 시뮬, 봇, 길찾기, 프로토콜). 서버와 클라이언트가 같이 씀 |
| `server/` | 권위 서버 (웹소켓) + 빌드된 웹 클라이언트 파일 서버 |
| `client/` | Flutter Web 화면 + `web/engine/rps_engine.js` (three.js 렌더·사운드·입력) |
| `rps_assets/` | 3D 모델(GLB), 아이콘, `catalog.json`, 에셋 생성 스크립트(`src/`) |
| `song/` | 맵 배경음악, 효과음 |
| `logo/` | 로고·앱 아이콘 원본 |
| `WORKLOG.md` | 작업 기록, 체크리스트, 결정 사항, 모델링 요청 목록 |

## 준비
- Flutter SDK (Dart 포함). 이 PC에서는 `~/Downloads/flutter` 에 있고 PATH에 없음:
  - `~/Downloads/flutter/bin/flutter.bat`
  - `~/Downloads/flutter/bin/cache/dart-sdk/bin/dart.exe`

## 실행
```sh
# 1) 에셋을 클라이언트로 복사 (모델·음악·효과음·아이콘·로고)
cd client
dart run tool/sync_assets.dart

# 2) 웹 빌드
flutter build web --release

# 3) 서버 실행 (게임 + 웹 페이지를 같이 제공)
cd ../server
dart run bin/server.dart --port 8090
```
- 브라우저에서 `http://localhost:8090` (같은 네트워크의 다른 PC는 서버가 출력한 LAN 주소)
- 서버 옵션: `--maps rps_arena,desert_ruins` `--bots 0.5`(봇 난이도 0~1) `--team 5`

## 인터넷으로 같이 하기 (무료)
1. 위 '실행'의 1)~2)로 웹 빌드를 만든다.
2. `scripts\start-public.bat` 더블클릭 (맥/리눅스: `scripts/start-public.sh`, `brew install cloudflared` 필요)
   - 게임 서버를 켜고 Cloudflare 무료 터널을 연다. 창에 `https://....trycloudflare.com` 주소가 나온다.
3. 그 주소를 친구들에게 보내면 브라우저로 접속 → 로비에서 **[온라인 참가]**.
- 두 창을 닫으면 종료. 주소는 켤 때마다 바뀐다. 주소를 아는 누구나 들어올 수 있다.
- Windows는 `%USERPROFILE%\tools\cloudflared.exe` 를 사용한다.

## 조작
WASD 이동 · 마우스 조준/좌클릭 사격 · 우클릭 정조준 · Space 점프 · Shift 앉기 ·
Q/E/C 스킬 · V 궁극기 · R 재장전 · 1/2/휠 무기 · B 상점(스폰룸)/사망 중 캐릭터 변경 · Tab 점수판 · Esc 메뉴

폰·태블릿(터치)은 자동으로 화면 버튼이 나온다: 왼쪽 엄지 이동, 오른쪽 드래그 시점, 발사 버튼을 누른 채 끌면 조준하며 사격.
가로 화면 권장. PC에서 확인하려면 주소에 `?touch`.

## 테스트
```sh
cd shared && dart test     # 게임 규칙·스킬·맵·봇 경기 (98개)
cd server && dart test     # 서버 접속·입력 검사 (3개)
cd client && flutter analyze
```
화면 확인용 헤드리스 캡처: `python client/tool/cdp_shot.py "http://localhost:8090/?screen=game&fakelock&debug" out.png --wait 12`
(개발용 주소 옵션: `?screen=lobby|game`, `&map=`, `&char=`, `&server=`, `&debug`, `&fakelock`, `&nopause=1`)

## 수치 조정 위치
- 역할(체력·받는/주는 피해·스킬 강도): `shared/lib/src/content/roles.dart`
- 총: `shared/lib/src/content/guns.dart` · 돈: `economy.dart` · 경기 규칙: `SimConfig` (`shared/lib/src/sim/sim.dart`)
- 스킬: `shared/lib/src/sim/skills_*.dart` · 봇: `shared/lib/src/sim/bot.dart`

## 에셋 수정 후
1. `rps_assets/src` 수정 → `python3 rps_assets/src/build.py` (+ `build_new.py`)
2. `catalog.json` 이 바뀌었으면 `cd shared && dart run tool/gen_catalog.dart`
3. `cd client && dart run tool/sync_assets.dart` → 다시 빌드
