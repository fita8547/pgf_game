# RPS 효과음 (70개)
- step_<바닥>_<walk|run>_<1~4>: 발소리. 바닥 = concrete, sand, snow, metal, wood, grass. 걸음마다 1~4 변형을 돌려 쓰고 피치를 ±5% 랜덤으로.
- 맵별 기본 바닥: rps_arena=concrete, desert_ruins=sand, frost_harbor=snow, neon_rooftops=metal, jungle_temple=grass
- gun_<총>_fire / _reload(1.85초, 1인칭 reload 애니메이션 타이밍과 맞춤)
- gun_shotgun_pump, gun_sniper_bolt: 발사 후 재생 (fire 클립 길이의 35% / 30% 지점)
- gun_launcher_explosion: 착탄 시
- dry_fire: 탄 없음, kill_ding / headshot_ding: 킬 알림, death_cat / death_dog: 사망 이펙트와 함께
- 다시 만들기: python3 sfx.py (music.py의 신시사이저 사용)
