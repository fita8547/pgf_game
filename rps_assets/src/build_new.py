"""new-modeling 에 들어간 glb 전부 다시 만들기.
python3 build_new.py [출력 폴더]   (기본: ../new-modeling)
아이콘 PNG 는 이 glb 들을 three.js 로 렌더해서 만든 것이라 여기서는 다시 만들지 않음.
효과음은 song/rps_sfx/sfx_new.py.
"""
import os, sys
import meshlib as M
import guns_hq, fp, map_arena, maps_more, fp_skills, fx_new, tp_build

def main(base):
    for d in ("anims", "guns", "fp_rigs", "maps", "fp_skills", "fx"):
        os.makedirs(f"{base}/glb/{d}", exist_ok=True)
    # 총 + 1인칭 리그 (muzzle 노드 추가)
    for gid, _n, _c, fn in guns_hq.GUNS:
        parts = fn()
        M.write_glb(gid, guns_hq.with_muzzle(gid, [dict(q) for q in parts]), f"{base}/glb/guns/{gid}.glb")
        rig, anims = fp.fp_rig(gid, parts)
        M.write_glb(f"fp_{gid}", rig, f"{base}/glb/fp_rigs/{gid}.glb", animations=anims)
    # 맵 3개 (수정본)
    M.write_glb("rps_arena", map_arena.build(), f"{base}/glb/maps/rps_arena.glb")
    for mid, _n, fn, *_ in maps_more.MAPS:
        if mid in ("neon_rooftops", "frost_harbor"):
            M.write_glb(mid, fn(), f"{base}/glb/maps/{mid}.glb")
    # 1인칭 스킬 동작
    for sid, fn in fp_skills.FP_SKILLS:
        P, A, _ex = fn()
        M.write_glb(f"fp_{sid}", P, f"{base}/glb/fp_skills/{sid}.glb", animations=A)
    # 이펙트 + 거점 깃발 + 게임 종료
    for fid, fn in fx_new.FX_NEW:
        P, a = fn()
        M.write_glb(fid, P, f"{base}/glb/fx/{fid}.glb", animations=[a] if a else None)
    # 3인칭 공용 애니메이션 (IK 계산이 있어 몇 분 걸림)
    tp_build.build(f"{base}/glb/anims/third_person.glb")
    print("done", base)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "new-modeling"))
