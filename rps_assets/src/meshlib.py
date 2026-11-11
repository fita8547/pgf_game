"""고품질 로우폴리 메시 엔진 + GLB 내보내기.

파츠(dict) 공통 키
  t   : 형태 종류 (rbox, box, cyl, sph, cap, lathe, ext, rock, empty)
  p   : 피벗 위치 (월드 좌표)
  r   : 회전 (도, XYZ 오일러)
  o   : 메시 오프셋 (피벗 기준 로컬) — 관절 피벗용
  c   : 색 (#rrggbb)   a: 투명도   m: 재질(metal/matte/rubber/glow/glass)
  n   : 노드 이름      parent: 부모 노드 이름 (부모는 회전이 없어야 함)
  sc  : 노드 스케일
"""
import json, math, struct
import numpy as np
from scipy.spatial import ConvexHull

METAL_COLORS = {"#3b4048", "#202328", "#b9bfc7", "#c9ced6", "#8e959e", "#2b2f35", "#6a717b", "#d9b45a"}

# ---------------------------------------------------------------- 유틸
def _orient(pos, idx, center=None, want=None):
    """삼각형이 바깥(또는 want 방향)을 보도록 감기 순서 정리."""
    out = []
    for a, b, c in idx:
        n = np.cross(pos[b] - pos[a], pos[c] - pos[a])
        if np.linalg.norm(n) < 1e-14:
            continue
        ref = want if want is not None else (pos[a] + pos[b] + pos[c]) / 3 - center
        out.append((a, c, b) if np.dot(n, ref) < 0 else (a, b, c))
    return out

def flatten(pos, nor, idx):
    """플랫 셰이딩: 정점 분리 + 면 노멀."""
    P, N, I = [], [], []
    for a, b, c in idx:
        n = np.cross(pos[b] - pos[a], pos[c] - pos[a])
        L = np.linalg.norm(n)
        if L < 1e-14: continue
        n = n / L
        k = len(P)
        P += [pos[a], pos[b], pos[c]]; N += [n, n, n]; I.append((k, k + 1, k + 2))
    return np.array(P), np.array(N), I

def merge(meshes):
    P, N, I, off = [], [], [], 0
    for p, n, i in meshes:
        if len(p) == 0: continue
        P.append(np.asarray(p)); N.append(np.asarray(n)); I += [(a + off, b + off, c + off) for a, b, c in i]; off += len(p)
    if not P: return np.zeros((0, 3)), np.zeros((0, 3)), []
    return np.vstack(P), np.vstack(N), I

# ---------------------------------------------------------------- 형태
def mesh_rbox(w, h, d, b=None, bseg=2):
    if b is None: b = min(0.012, 0.14 * min(w, h, d))
    b = min(b, 0.49 * min(w, h, d))
    hw, hh, hd = w / 2 - b, h / 2 - b, d / 2 - b
    pts = []
    if b < 1e-5:
        pts = [(sx * w / 2, sy * h / 2, sz * d / 2) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    else:
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    for i in range(bseg + 1):
                        th = math.pi / 2 * i / bseg
                        for j in range(bseg + 1):
                            ph = math.pi / 2 * j / bseg
                            pts.append((sx * (hw + b * math.sin(th) * math.cos(ph)), sy * (hh + b * math.cos(th)), sz * (hd + b * math.sin(th) * math.sin(ph))))
    pts = np.unique(np.round(np.array(pts), 7), axis=0)
    hull = ConvexHull(pts)
    used = sorted(set(hull.simplices.flatten()))
    remap = {v: k for k, v in enumerate(used)}
    pos = pts[used]
    idx = [(remap[a], remap[b_], remap[c]) for a, b_, c in hull.simplices]
    idx = _orient(pos, idx, center=np.zeros(3))
    if b < 1e-5:
        return flatten(pos, None, idx)
    inner = np.array([hw, hh, hd])
    nor = pos - np.clip(pos, -inner, inner)
    L = np.linalg.norm(nor, axis=1, keepdims=True)
    nor = nor / np.maximum(L, 1e-9)
    return pos, nor, idx

def mesh_lathe(profile, seg=16, smooth=None, crease=38, a0=0.0, a1=360.0):
    """profile: [(r, y), ...] 아래→위, 바깥이 오른쪽."""
    if smooth is None: smooth = seg >= 10
    prof = [np.array(p, float) for p in profile]
    nseg = len(prof) - 1
    n2 = []
    for k in range(nseg):
        dr, dy = prof[k + 1] - prof[k]
        v = np.array([dy, -dr]); L = np.linalg.norm(v)
        n2.append(v / L if L > 1e-12 else np.array([1.0, 0.0]))
    full = abs(a1 - a0) >= 359.9
    cols = seg + (0 if full else 1)
    angs = [math.radians(a0 + (a1 - a0) * i / seg) for i in range(cols)]
    P, N, I = [], [], []
    for k in range(nseg):
        # 프로파일 정점 노멀 (주름 각 이하이면 이웃과 평균)
        def vn(idx_v, side):
            nn = n2[k]
            nb = k - 1 if side == 0 else k + 1
            if 0 <= nb < nseg:
                ang = math.degrees(math.acos(max(-1, min(1, float(np.dot(n2[k], n2[nb]))))))
                if ang < crease:
                    nn = n2[k] + n2[nb]; nn = nn / np.linalg.norm(nn)
            return nn
        na, nb_ = vn(k, 0), vn(k + 1, 1)
        base = len(P)
        for (pr, py), nn in ((prof[k], na), (prof[k + 1], nb_)):
            for a in angs:
                P.append((pr * math.sin(a), py, pr * math.cos(a)))
                N.append((nn[0] * math.sin(a), nn[1], nn[0] * math.cos(a)))
        for i in range(seg):
            i2 = (i + 1) % cols if full else i + 1
            a, b, c, d = base + i, base + i2, base + cols + i2, base + cols + i
            I += [(a, b, c), (a, c, d)]
    pos, nor = np.array(P), np.array(N)
    # 감기 순서: 노멀 방향 기준
    out = []
    for a, b, c in I:
        n = np.cross(pos[b] - pos[a], pos[c] - pos[a])
        if np.linalg.norm(n) < 1e-14: continue
        ref = nor[a] + nor[b] + nor[c]
        out.append((a, c, b) if np.dot(n, ref) < 0 else (a, b, c))
    if not smooth:
        return flatten(pos, nor, out)
    return pos, nor, out

def mesh_cyl(rt, rb, h, seg=16, bevel=0.0):
    seg = int(seg)
    if bevel > 0:
        b = min(bevel, 0.4 * h, 0.4 * max(rt, rb))
        prof = [(0, -h / 2), (rb - b, -h / 2), (rb, -h / 2 + b), (rt, h / 2 - b), (rt - b, h / 2), (0, h / 2)]
    else:
        prof = [(0, -h / 2), (rb, -h / 2), (rt, h / 2), (0, h / 2)]
    prof = [p for i, p in enumerate(prof) if i == 0 or p != prof[i - 1]]
    if rt <= 1e-9: prof = [p for p in prof if not (p[0] <= 1e-9 and p[1] == h / 2)] + [(0, h / 2)]
    return mesh_lathe(prof, seg=seg, smooth=seg >= 10)

def mesh_sph(r, ws=20, hs=14, smooth=True):
    prof = [(r * math.sin(math.pi * j / hs), -r * math.cos(math.pi * j / hs)) for j in range(hs + 1)]
    return mesh_lathe(prof, seg=ws, smooth=smooth, crease=80)

def mesh_capsule(r, length, seg=16, rings=5, r2=None):
    """Y축 캡슐. length = 양 끝 구 중심 간 거리. r2가 있으면 위쪽 반지름(테이퍼)."""
    r2 = r if r2 is None else r2
    prof = []
    for j in range(rings + 1):
        a = -math.pi / 2 + math.pi / 2 * j / rings
        prof.append((r * math.cos(a), -length / 2 + r * math.sin(a)))
    for j in range(rings + 1):
        a = math.pi / 2 * j / rings
        prof.append((r2 * math.cos(a), length / 2 + r2 * math.sin(a)))
    prof[0] = (0.0, prof[0][1]); prof[-1] = (0.0, prof[-1][1])
    return mesh_lathe(prof, seg=seg, smooth=True, crease=60)

def mesh_rock(sx, sy, sz, n=18, seed=1, jitter=0.25):
    rng = np.random.default_rng(seed)
    v = rng.normal(size=(n, 3)); v /= np.linalg.norm(v, axis=1, keepdims=True)
    v *= (1 - jitter + jitter * rng.random((n, 1)))
    v *= np.array([sx, sy, sz]) / 2
    hull = ConvexHull(v)
    pos = v
    idx = _orient(pos, [tuple(s) for s in hull.simplices], center=np.zeros(3))
    return flatten(pos, None, idx)

# ---- 2D 압출
def _area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))

def _earclip(poly):
    pts = list(range(len(poly)))
    tris, guard = [], 0
    def inside(p, a, b, c):
        def s(p1, p2, p3): return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
        d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
    while len(pts) > 3 and guard < 5000:
        guard += 1
        ear = False
        for k in range(len(pts)):
            i0, i1, i2 = pts[k - 1], pts[k], pts[(k + 1) % len(pts)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if cr <= 1e-12: continue
            if any(inside(poly[j], a, b, c) for j in pts if j not in (i0, i1, i2)): continue
            tris.append((i0, i1, i2)); pts.pop(k); ear = True; break
        if not ear: pts.pop(0)  # 퇴화 정점 제거
    if len(pts) == 3: tris.append(tuple(pts))
    return tris

def _inset(poly, d):
    n = len(poly); out = []
    for i in range(n):
        p0, p1, p2 = np.array(poly[i - 1]), np.array(poly[i]), np.array(poly[(i + 1) % n])
        e1, e2 = p1 - p0, p2 - p1
        n1 = np.array([-e1[1], e1[0]]) / max(np.linalg.norm(e1), 1e-12)
        n2 = np.array([-e2[1], e2[0]]) / max(np.linalg.norm(e2), 1e-12)
        m = n1 + n2; dot = 1 + float(np.dot(n1, n2))
        off = m * d / dot if dot > 1e-3 else n1 * d
        if np.linalg.norm(off) > 2.5 * d: off = off / np.linalg.norm(off) * 2.5 * d
        out.append(tuple(p1 + off))
    return out

def mesh_ext(pts, w, c=0.0):
    """pts: (z, y) 옆모습 폴리곤, w: X 두께, c: 챔퍼."""
    poly = [tuple(map(float, p)) for p in pts]
    if _area(poly) < 0: poly = poly[::-1]
    c = min(c, w * 0.45)
    inner = _inset(poly, c) if c > 0 else poly
    tri = _earclip(inner)
    to3 = lambda q, x: np.array([x, q[1], q[0]])
    meshes = []
    for sgn in (1, -1):
        P = [to3(q, sgn * w / 2) for q in inner]
        N = [np.array([sgn, 0, 0.0])] * len(P)
        idx = _orient(np.array(P), tri, want=np.array([sgn, 0, 0.0]))
        meshes.append((np.array(P), np.array(N), idx))
    n = len(poly); xs = w / 2 - c
    P, N, I = [], [], []
    def quad(a, b, cc, d, want):
        k = len(P); P.extend([a, b, cc, d])
        nn = np.cross(b - a, cc - a); L = np.linalg.norm(nn)
        if L < 1e-14:
            nn = np.cross(cc - a, d - a); L = np.linalg.norm(nn)
            if L < 1e-14: P[k:] = []; return
        nn = nn / L
        if np.dot(nn, want) < 0: nn = -nn; I.extend([(k, k + 2, k + 1), (k, k + 3, k + 2)])
        else: I.extend([(k, k + 1, k + 2), (k, k + 2, k + 3)])
        N.extend([nn] * 4)
    for i in range(n):
        p0, p1 = poly[i], poly[(i + 1) % n]
        du, dv = p1[0] - p0[0], p1[1] - p0[1]
        L = math.hypot(du, dv)
        if L < 1e-9: continue
        out = np.array([0, -du / L, dv / L])  # 바깥 노멀 (z=u, y=v → 3D (0, y, z))
        out = np.array([0, out[1], out[2]])
        # (u,v) 바깥 노멀 = (dv, -du) → 3D (x=0, y=-du, z=dv)
        o3 = np.array([0.0, -du / L, dv / L])
        quad(to3(p0, -xs), to3(p1, -xs), to3(p1, xs), to3(p0, xs), o3)
        if c > 0:
            q0, q1 = inner[i], inner[(i + 1) % n]
            quad(to3(p0, xs), to3(p1, xs), to3(q1, w / 2), to3(q0, w / 2), o3 + np.array([1, 0, 0]))
            quad(to3(p0, -xs), to3(p1, -xs), to3(q1, -w / 2), to3(q0, -w / 2), o3 + np.array([-1, 0, 0]))
    meshes.append((np.array(P) if P else np.zeros((0, 3)), np.array(N) if N else np.zeros((0, 3)), I))
    return merge(meshes)

def build_mesh(part):
    t, s = part["t"], part["s"]
    if t == "rbox": m = mesh_rbox(*s["size"], b=s.get("b"), bseg=s.get("bseg", 2))
    elif t == "box":
        w, h, d = s
        m = mesh_rbox(w, h, d, b=min(0.006, 0.12 * min(w, h, d)), bseg=1)
    elif t == "cyl":
        rt, rb, h, seg = s[:4]
        seg = int(seg)
        if seg >= 10: seg = max(seg, 20)
        m = mesh_cyl(rt, rb, h, seg=seg, bevel=s[4] if len(s) > 4 else (min(0.004, 0.15 * h) if seg >= 10 and rt > 0 and rb > 0 else 0))
    elif t == "sph":
        r, ws, hs = s
        if ws >= 8: m = mesh_sph(r, max(ws, 22), max(hs, 14), smooth=True)
        else: m = mesh_sph(r, int(ws), int(hs), smooth=False)
    elif t == "cap": m = mesh_capsule(s["r"], s["l"], seg=s.get("seg", 18), r2=s.get("r2"))
    elif t == "lathe": m = mesh_lathe(s["prof"], seg=s.get("seg", 20), smooth=s.get("smooth"), a0=s.get("a0", 0), a1=s.get("a1", 360))
    elif t == "ext": m = mesh_ext(s["pts"], s["w"], s.get("c", 0.0))
    elif t == "rock": m = mesh_rock(*s["size"], n=s.get("n", 18), seed=s.get("seed", 1), jitter=s.get("j", 0.25))
    elif t == "empty": return None
    else: raise ValueError(t)
    pos, nor, idx = m
    o = np.array(part.get("o", (0, 0, 0)), float)
    return np.asarray(pos, np.float32) + o.astype(np.float32), np.asarray(nor, np.float32), np.asarray(idx, np.uint32)

# ---------------------------------------------------------------- GLB
def quat(r):
    x, y, z = [math.radians(v) / 2 for v in r]
    qx = (math.sin(x), 0, 0, math.cos(x)); qy = (0, math.sin(y), 0, math.cos(y)); qz = (0, 0, math.sin(z), math.cos(z))
    def mul(a, b):
        ax, ay, az, aw = a; bx, by, bz, bw = b
        return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)
    return list(mul(mul(qx, qy), qz))

def srgb_lin(hexc):
    v = [int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in v]

def material(c, a, m, mn=None):
    col = srgb_lin(c) + [1.0]
    metal = m == "metal" or (m is None and c in METAL_COLORS)
    mat = {"name": mn or f"{c}{'_' + m if m else ''}{'_a' + str(a) if a is not None else ''}",
           "pbrMetallicRoughness": {"baseColorFactor": col,
                                    "metallicFactor": 0.75 if metal else 0.0,
                                    "roughnessFactor": 0.38 if metal else (0.95 if m == "rubber" else 0.62)}}
    if m == "glow":
        mat["emissiveFactor"] = srgb_lin(c); mat["pbrMetallicRoughness"]["roughnessFactor"] = 0.4
    if m == "glass":
        a = 0.35 if a is None else a
    if a is not None:
        col[3] = a; mat["alphaMode"] = "BLEND"; mat["doubleSided"] = True
    return mat

def write_glb(name, parts, path, animations=None):
    """animations: [{"name": str, "channels": [{"node": 이름, "path": "translation"|"rotation", "times": [...], "values": [...]}]}]
    rotation 값은 오일러(도) 리스트로 주면 쿼터니언으로 변환. translation 값은 노드의 레스트 위치에 더해짐(오프셋)."""
    gl = {"asset": {"version": "2.0", "generator": "rps-models-hq"}, "scene": 0,
          "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "children": []}],
          "meshes": [], "materials": [], "accessors": [], "bufferViews": [], "buffers": []}
    blob, mats, by_name, tris = bytearray(), {}, {}, 0
    def add_view(arr, target):
        while len(blob) % 4: blob.append(0)
        off = len(blob); blob.extend(arr.tobytes())
        gl["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes, "target": target})
        return len(gl["bufferViews"]) - 1
    used = set()
    for i, part in enumerate(parts):
        nm = part.get("n", f"part_{i}")
        if nm in used: nm = f"{nm}_{i}"
        used.add(nm); part["_name"] = nm
        node = {"name": nm}
        built = build_mesh(part)
        if built is not None:
            pos, nor, idx = built
            if len(idx) == 0: built = None
        if built is not None:
            mk = (part["c"], part.get("a"), part.get("m")) + ((part["mn"],) if part.get("mn") else ())   # mn: 머티리얼 이름 지정
            if mk not in mats:
                mats[mk] = len(gl["materials"]); gl["materials"].append(material(*mk))
            vp = add_view(pos, 34962)
            gl["accessors"].append({"bufferView": vp, "componentType": 5126, "count": len(pos), "type": "VEC3",
                                    "min": pos.min(0).tolist(), "max": pos.max(0).tolist()})
            ap = len(gl["accessors"]) - 1
            vn = add_view(nor, 34962)
            gl["accessors"].append({"bufferView": vn, "componentType": 5126, "count": len(nor), "type": "VEC3"}); an = ap + 1
            if len(pos) < 65535:
                ia = idx.astype(np.uint16).flatten(); ct = 5123
            else:
                ia = idx.astype(np.uint32).flatten(); ct = 5125
            vi = add_view(ia, 34963)
            gl["accessors"].append({"bufferView": vi, "componentType": ct, "count": int(ia.size), "type": "SCALAR"})
            gl["meshes"].append({"name": nm, "primitives": [{"attributes": {"POSITION": ap, "NORMAL": an}, "indices": an + 1, "material": mats[mk]}]})
            node["mesh"] = len(gl["meshes"]) - 1
            tris += len(idx)
        par = part.get("parent")
        p = np.array(part["p"], float)
        if par and part.get("local"):
            loc = p                                   # 이미 부모 기준 로컬 좌표
        elif par:
            pp = by_name[par]
            assert not any(pp["r"]), f"부모 {par}는 회전이 없어야 함"
            loc = p - np.array(pp.get("_world", pp["p"]), float)
        else:
            loc = p
        part["_world"] = list(p)
        if np.any(np.abs(loc) > 1e-9): node["translation"] = [float(v) for v in loc]
        if any(part.get("r", (0, 0, 0))): node["rotation"] = quat(part["r"])
        if part.get("sc"): node["scale"] = list(part["sc"])
        gl["nodes"].append(node)
        ni = len(gl["nodes"]) - 1
        part["_node"] = ni
        if par: gl["nodes"][by_name[par]["_node"]].setdefault("children", []).append(ni)
        else: gl["nodes"][0]["children"].append(ni)
        by_name[part.get("n", nm)] = part
    if animations:
        gl["animations"] = []
        node_idx = {q.get("n", q.get("_name")): q["_node"] for q in parts}
        node_rest = {q.get("n"): gl["nodes"][q["_node"]].get("translation", [0, 0, 0]) for q in parts}
        for anim in animations:
            A = {"name": anim["name"], "channels": [], "samplers": []}
            for ch in anim["channels"]:
                if ch["node"] not in node_idx: continue
                t = np.array(ch["times"], np.float32)
                if ch["path"] == "rotation":
                    v = np.array([quat(e) for e in ch["values"]], np.float32)
                    # 쿼터니언 부호 연속성
                    for i in range(1, len(v)):
                        if np.dot(v[i], v[i - 1]) < 0: v[i] = -v[i]
                    typ = "VEC4"
                elif ch["path"] == "scale":
                    v = np.array(ch["values"], np.float32); typ = "VEC3"
                else:
                    rest = np.array(node_rest[ch["node"]], np.float32)
                    v = np.array(ch["values"], np.float32) + rest; typ = "VEC3"
                vt = add_view(t, None) if False else None
                while len(blob) % 4: blob.append(0)
                off = len(blob); blob.extend(t.tobytes())
                gl["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": t.nbytes})
                gl["accessors"].append({"bufferView": len(gl["bufferViews"]) - 1, "componentType": 5126, "count": len(t), "type": "SCALAR",
                                        "min": [float(t.min())], "max": [float(t.max())]})
                ti = len(gl["accessors"]) - 1
                while len(blob) % 4: blob.append(0)
                off = len(blob); blob.extend(v.tobytes())
                gl["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": v.nbytes})
                gl["accessors"].append({"bufferView": len(gl["bufferViews"]) - 1, "componentType": 5126, "count": len(v), "type": typ})
                vi = len(gl["accessors"]) - 1
                A["samplers"].append({"input": ti, "output": vi, "interpolation": "LINEAR"})
                A["channels"].append({"sampler": len(A["samplers"]) - 1, "target": {"node": node_idx[ch["node"]], "path": ch["path"]}})
            gl["animations"].append(A)
    while len(blob) % 4: blob.append(0)
    gl["buffers"].append({"byteLength": len(blob)})
    js = json.dumps(gl, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)
    for part in parts:
        part.pop("_node", None); part.pop("_name", None); part.pop("_world", None)
    return tris
