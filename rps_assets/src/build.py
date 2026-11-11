"""전체 빌드: 총기 7, 캐릭터 12(로비 모션), 1인칭 팔 12, 1인칭 총 리그 7, 스킬 48, 맵 1."""
import json, os, shutil
import meshlib as M
import guns_hq, chars_hq, fp, map_arena, maps_more, fx
from build_all import SKILLS

ROLE = {"boulder": "디펜서", "cardboard": "디펜서", "shear": "디펜서",
        "pebble": "어택", "origami": "어택", "snip": "어택",
        "gem": "힐러", "scroll": "힐러", "needle": "힐러",
        "quake": "컨트롤러", "inkwell": "컨트롤러", "staple": "컨트롤러"}
ORDER = ["디펜서", "어택", "힐러", "컨트롤러"]

def main():
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out2")
    if os.path.exists(base): shutil.rmtree(base)
    for d in ("guns", "characters", "fp_arms", "fp_rigs", "skills", "maps", "fx"):
        os.makedirs(f"{base}/glb/{d}", exist_ok=True)
    data = {"roles": ORDER, "guns": [], "characters": [], "maps": [], "fx": []}
    gun_parts = {}
    for gid, name, cls, fn in guns_hq.GUNS:
        parts = fn(); gun_parts[gid] = parts
        t = M.write_glb(gid, guns_hq.with_muzzle(gid, [dict(q) for q in parts]), f"{base}/glb/guns/{gid}.glb")
        rig, anims = fp.fp_rig(gid, parts)
        t2 = M.write_glb(f"fp_{gid}", rig, f"{base}/glb/fp_rigs/{gid}.glb", animations=anims)
        data["guns"].append({"id": gid, "name": name, "class": cls, "tris": t, "file": f"glb/guns/{gid}.glb",
                             "fp": f"glb/fp_rigs/{gid}.glb", "anims": [a["name"] for a in anims], "parts": len(parts),
                             "ads": {k: fp.GUN_FP[gid][k] for k in ("hold", "sight", "ads_fov", "eye", "scope")} | {"overlay": fp.GUN_FP[gid].get("overlay", False)}})
    chars = sorted(chars_hq.CHARS, key=lambda c: (ORDER.index(ROLE[c[0]]), c[0]))
    for cid, name, _fac, _r, race, sex, fn in chars:
        parts = fn()
        extra, lobby = fp.lobby_extras(parts)
        t = M.write_glb(cid, parts + extra, f"{base}/glb/characters/{cid}.glb", animations=[lobby])
        arms = fp.fp_arms(parts, cid)
        ta = M.write_glb(f"fp_arms_{cid}", arms, f"{base}/glb/fp_arms/{cid}.glb")
        skills = []
        os.makedirs(f"{base}/glb/skills/{cid}", exist_ok=True)
        for sid, key, sname, desc, cd, sfn in SKILLS[cid]:
            sp = sfn()
            ts = M.write_glb(sid, sp, f"{base}/glb/skills/{cid}/{sid}.glb")
            skills.append({"id": sid, "key": key, "name": sname, "desc": desc, "cd": cd, "tris": ts, "file": f"glb/skills/{cid}/{sid}.glb"})
        data["characters"].append({"id": cid, "name": name, "role": ROLE[cid], "race": race, "sex": sex, "tris": t, "arms_tris": ta,
                                   "file": f"glb/characters/{cid}.glb", "fp_arms": f"glb/fp_arms/{cid}.glb", "skills": skills, "parts": len(parts)})
    mp = map_arena.build()
    tm = M.write_glb("rps_arena", mp, f"{base}/glb/maps/rps_arena.glb")
    data["maps"].append({"id": "rps_arena", "name": "RPS 아레나", "size": "64 × 48 m", "tris": tm, "file": "glb/maps/rps_arena.glb",
                         "desc": "3라인 대전 맵. 왼쪽 창고, 가운데 기념비 광장, 오른쪽 고가 다리. A팀 주황 / B팀 파랑 스폰.", "fp_cam": {"pos": (-3.5, 1.65, 15.5), "look": (0, 1.5, 0)}})
    for mid, mname, mfn, size, desc, cam in maps_more.MAPS:
        tmm = M.write_glb(mid, mfn(), f"{base}/glb/maps/{mid}.glb")
        data["maps"].append({"id": mid, "name": mname, "size": size, "tris": tmm, "file": f"glb/maps/{mid}.glb", "desc": desc, "fp_cam": cam})
    for fid, fname, ffn in fx.FX:
        fp_, fa = ffn()
        tf = M.write_glb(fid, fp_, f"{base}/glb/fx/{fid}.glb", animations=[fa])
        data["fx"].append({"id": fid, "name": fname, "tris": tf, "file": f"glb/fx/{fid}.glb", "anim": fa["name"]})
    with open(f"{base}/catalog.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    tot = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(base) for fn in fns)
    print("guns", len(data["guns"]), "chars", len(data["characters"]), "skills", sum(len(c["skills"]) for c in data["characters"]),
          "maps", len(data["maps"]), "fx", len(data["fx"]), "total MB", round(tot / 1e6, 2))
    for c in data["characters"]: print(c["id"], c["tris"], c["arms_tris"])
    for g in data["guns"]: print(g["id"], g["tris"])

if __name__ == "__main__":
    main()
