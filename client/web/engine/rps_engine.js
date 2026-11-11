// RPS render/audio/input engine (three.js). Game logic lives in Dart; Dart
// drives this through window.rpsEngine (see lib/engine/engine.dart).
//
// Conventions (same as the assets / shared sim): metres, Y-up. Yaw 0 looks
// toward -Z, positive yaw turns toward +X. Character models face +Z.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Audio } from './audio.js';
import { Input } from './input.js';

const BASE = 'game/';
const DEBUG = new URLSearchParams(location.search).has('debug');
const loader = new GLTFLoader();
const gltfCache = new Map();

function loadGltf(path) {
  if (!gltfCache.has(path)) {
    gltfCache.set(path, new Promise((ok, fail) => loader.load(BASE + path, (g) => {
      g.scene.traverse((o) => {
        if (!o.isMesh) return;
        const m = o.material;
        // Solid glow strips bloom; see-through glow (spawn pads, fx) stays softer.
        if (m && m.name && m.name.includes('glow')) m.emissiveIntensity = m.transparent ? 0.9 : 2.6;
        if (m && m.transparent) m.depthWrite = false;
      });
      ok(g);
    }, undefined, fail)));
  }
  return gltfCache.get(path);
}

// Draw-call reduction (brief §6-2): merge opaque leaf meshes that share a
// material and an anchor node into one mesh attached to that anchor.
// Maps anchor everything to the map root; characters anchor to the nearest
// non-mesh ancestor (the bone), so animation still works.
function mergeMeshes(root, anchorOf) {
  root.updateMatrixWorld(true);
  const groups = new Map();
  root.traverse((o) => {
    if (!o.isMesh || o.isSkinnedMesh || o.children.length) return;
    const mat = o.material;
    if (!mat || Array.isArray(mat) || mat.transparent) return;
    const anchor = anchorOf(o);
    if (!anchor) return;
    const g = o.geometry;
    const key = `${anchor.uuid}|${mat.uuid}|${Object.keys(g.attributes).sort().join(',')}|${g.index ? 'i' : 'n'}`;
    if (!groups.has(key)) groups.set(key, { anchor, mat, items: [] });
    groups.get(key).items.push(o);
  });
  let merged = 0;
  const inv = new THREE.Matrix4(), m = new THREE.Matrix4();
  for (const { anchor, mat, items } of groups.values()) {
    if (items.length < 2) continue;
    inv.copy(anchor.matrixWorld).invert();
    const geoms = items.map((o) => o.geometry.clone().applyMatrix4(m.multiplyMatrices(inv, o.matrixWorld)));
    const geo = mergeGeometries(geoms, false);
    for (const g of geoms) g.dispose();
    if (!geo) continue;
    const mesh = new THREE.Mesh(geo, mat);
    mesh.name = 'merged';
    mesh.castShadow = items[0].castShadow;
    mesh.receiveShadow = items[0].receiveShadow;
    anchor.add(mesh);
    for (const o of items) o.parent.remove(o);
    merged += items.length;
  }
  return merged;
}

const nearestNonMesh = (o) => { let a = o.parent; while (a && a.isMesh) a = a.parent; return a; };

function findNode(root, name) {
  let out = null;
  root.traverse((o) => { if (!out && o.name === name) out = o; });
  return out;
}

const MAP_LOOK = {
  rps_arena: { sky: 0x9cc4ea, fog: [60, 160], sun: 1.6, hemi: 1.1 },
  desert_ruins: { sky: 0xf1d6a2, fog: [50, 150], sun: 1.9, hemi: 1.0 },
  frost_harbor: { sky: 0xcfe2f3, fog: [40, 130], sun: 1.3, hemi: 1.3 },
  neon_rooftops: { sky: 0x1a1036, fog: [45, 150], sun: 0.5, hemi: 0.7 },
  jungle_temple: { sky: 0x9cc7a2, fog: [40, 120], sun: 1.4, hemi: 1.1 },
};

class Engine {
  constructor() {
    this.canvas = document.getElementById('rps3d');
    this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, powerPreference: 'high-performance' });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(70, 1, 0.05, 500);
    this.camera.rotation.order = 'YXZ';
    this.world = new THREE.Group();
    this.dynamic = new THREE.Group();
    this.scene.add(this.world, this.dynamic);
    this._lights(this.scene);

    // Viewmodel: own scene + camera, drawn after the world with a cleared
    // depth buffer so the gun never clips into walls (brief §6-5).
    this.vmScene = new THREE.Scene();
    this.vmCamera = new THREE.PerspectiveCamera(70, 1, 0.01, 10);
    this.vmScene.add(new THREE.HemisphereLight(0xffffff, 0x445066, 1.6));
    const vmSun = new THREE.DirectionalLight(0xffffff, 1.6);
    vmSun.position.set(0.5, 1, 0.6);
    this.vmScene.add(vmSun);
    this.vmRoot = new THREE.Group();
    this.vmScene.add(this.vmRoot);
    this.badges = new THREE.Group();
    this.vmScene.add(this.badges);

    // Lobby: separate scene with a turntable.
    this.lobbyScene = new THREE.Scene();
    this.lobbyScene.background = null;
    this.lobbyCamera = new THREE.PerspectiveCamera(32, 1, 0.1, 50);
    this._lights(this.lobbyScene, true);
    const disc = new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.2, 0.08, 48),
      new THREE.MeshStandardMaterial({ color: 0x232a5c, roughness: 0.5, metalness: 0.2 }));
    disc.position.y = -0.04;
    disc.receiveShadow = true;
    const ring = new THREE.Mesh(new THREE.TorusGeometry(1.15, 0.025, 8, 64),
      new THREE.MeshStandardMaterial({ color: 0xe8b04a, emissive: 0xe8b04a, emissiveIntensity: 1.5 }));
    ring.rotation.x = Math.PI / 2;
    this.lobbyScene.add(disc, ring);
    this.lobbyTurn = new THREE.Group();
    this.lobbyScene.add(this.lobbyTurn);
    this.lobbyOffset = 0;

    this.composer = new EffectComposer(this.renderer);
    this.renderPass = new RenderPass(this.scene, this.camera);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.55, 0.45, 1.0);
    this.composer.addPass(this.renderPass);
    this.composer.addPass(this.bloom);
    this.composer.addPass(new OutputPass());

    this.mode = 'none';
    this.mixers = new Set();
    this.players = new Map();
    this.projectiles = new Map();
    this.deployables = new Map();

    this.fx = [];
    this.vm = null;
    this.vmVisible = true;
    this.clock = new THREE.Clock();
    this.audio = new Audio();
    this.input = new Input(this.canvas);
    this.tick = null;
    this.mapId = null;

    window.addEventListener('resize', () => this._resize());
    this._resize();
    this.renderer.setAnimationLoop(() => this._frame());
  }

  _lights(scene, lobby = false) {
    const hemi = new THREE.HemisphereLight(0xdfe9ff, 0x5a5146, lobby ? 1.4 : 1.1);
    const sun = new THREE.DirectionalLight(0xfff2dd, lobby ? 2.2 : 1.6);
    sun.position.set(lobby ? 2 : 30, lobby ? 4 : 50, lobby ? 3 : 20);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const s = lobby ? 3 : 48;
    Object.assign(sun.shadow.camera, { left: -s, right: s, top: s, bottom: -s, near: 1, far: lobby ? 20 : 160 });
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = 0.02;
    scene.add(hemi, sun);
    if (!lobby) { this.hemi = hemi; this.sun = sun; }
    if (lobby) {
      const rim = new THREE.DirectionalLight(0x6f9bff, 1.6);
      rim.position.set(-3, 2.5, -3);
      scene.add(rim);
    }
  }

  _resize() {
    const w = window.innerWidth, h = window.innerHeight;
    this.renderer.setSize(w, h, false);
    this.canvas.style.width = w + 'px';
    this.canvas.style.height = h + 'px';
    this.composer.setSize(w, h);
    for (const c of [this.camera, this.vmCamera, this.lobbyCamera]) { c.aspect = w / h; c.updateProjectionMatrix(); }
  }

  _frame() {
    const dt = Math.min(this.clock.getDelta(), 0.1);
    // Count draw calls across all passes of this frame (shown by stats()).
    this.renderer.info.autoReset = false;
    this.renderer.info.reset();
    if (this.tick) {
      try { this.tick(dt); } catch (e) { console.error(e); }
    }
    for (const m of this.mixers) m.update(dt);
    this._applyAim();
    this._updateFx(dt);
    this._updateDamage(dt);
    if (DEBUG && (this._dbgT = (this._dbgT || 0) + 1) > 30) {
      this._dbgT = 0;
      const vm = this.vm;
      console.log('[rps] frame mode', this.mode, 'vmVisible', this.vmVisible, 'vm', !!vm,
        vm ? vm.fpRoot.position.toArray().map((v) => v.toFixed(3)).join(',') : '-',
        vm ? JSON.stringify(vm.hold) : '', 'cam', this.camera.position.toArray().map((v) => v.toFixed(2)).join(','));
    }
    const r = this.renderer;
    if (this.mode === 'lobby') {
      this.lobbyTurn.rotation.y += dt * 0.35;
      r.autoClear = true;
      r.setClearColor(0x000000, 0);
      r.render(this.lobbyScene, this.lobbyCamera);
    } else if (this.mode === 'game') {
      r.autoClear = true;
      this.composer.render(dt);
      if (this.vmVisible || this.badges.children.length) {
        r.autoClear = false;
        r.clearDepth();
        this.vmRoot.visible = this.vmVisible;
        r.render(this.vmScene, this.vmCamera);
      }
    } else {
      r.autoClear = true;
      r.setClearColor(0x000000, 0);
      r.clear();
    }
  }

  // Graphics quality: 0 low (no shadows/bloom, lower resolution),
  // 1 medium, 2 high.
  setQuality(q) {
    this.quality = q;
    const dpr = window.devicePixelRatio || 1;
    this.renderer.setPixelRatio(q === 0 ? Math.min(dpr, 1) * 0.75 : q === 1 ? Math.min(dpr, 1.25) : Math.min(dpr, 2));
    this.renderer.shadowMap.enabled = q > 0;
    const size = q === 2 ? 2048 : 1024;
    for (const light of [this.sun]) {
      if (light && light.shadow.mapSize.x !== size) {
        light.shadow.mapSize.set(size, size);
        if (light.shadow.map) { light.shadow.map.dispose(); light.shadow.map = null; }
      }
    }
    this.bloom.enabled = q > 0;
    // Materials must recompile when shadows toggle.
    this.scene.traverse((o) => { if (o.material) o.material.needsUpdate = true; });
    this._resize();
  }

  // Dev: draw calls / triangles of the last frame and loaded object counts.
  stats() {
    const i = this.renderer.info;
    let meshes = 0;
    this.scene.traverse((o) => { if (o.isMesh) meshes++; });
    return { calls: i.render.calls, triangles: i.render.triangles, meshes, geometries: i.memory.geometries };
  }

  // ------------------------------------------------------------- lobby --
  async showLobby(charId, gunId) {
    this.mode = 'lobby';
    this.canvas.style.filter = '';
    const token = (this._lobbyToken = {});
    const [ch, gun] = await Promise.all([loadGltf(`glb/characters/${charId}.glb`), loadGltf(`glb/guns/${gunId}.glb`)]);
    if (token !== this._lobbyToken) return;
    for (const c of [...this.lobbyTurn.children]) { this.lobbyTurn.remove(c); }
    if (this.lobbyMixer) this.mixers.delete(this.lobbyMixer);
    const model = ch.scene.clone(true);
    model.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    const socket = findNode(model, 'weapon_socket_R');
    if (socket) socket.add(gun.scene.clone(true));
    const clip = ch.animations.find((a) => a.name === 'lobby_idle');
    if (clip) {
      this.lobbyMixer = new THREE.AnimationMixer(model);
      this.lobbyMixer.clipAction(clip).play();
      this.mixers.add(this.lobbyMixer);
    }
    this.lobbyTurn.add(model);
    this.lobbyTurn.rotation.y = 0.5;
    this._lobbyCam();
  }

  setLobbyOffset(x) { this.lobbyOffset = x; this._lobbyCam(); }

  _lobbyCam() {
    // Shift the camera so the model sits at screen-x offset (-1..1).
    const c = this.lobbyCamera;
    c.position.set(-this.lobbyOffset * 1.6, 1.15, 5.2);
    c.lookAt(-this.lobbyOffset * 1.6, 0.95, 0);
  }

  hideAll() {
    this.mode = 'none';
    this.canvas.style.filter = '';
  }

  // -------------------------------------------------------------- game --
  async loadMap(mapId) {
    const g = await loadGltf(`glb/maps/${mapId}.glb`);
    this.world.clear();
    const map = g.scene.clone(true);
    map.traverse((o) => {
      if (!o.isMesh) return;
      const m = o.material;
      const seeThrough = m && m.transparent;
      o.castShadow = !seeThrough;
      o.receiveShadow = true;
    });
    const merged = mergeMeshes(map, () => map);
    if (DEBUG) console.log('[rps] map merge', mapId, 'meshes merged', merged);
    this.world.add(map);
    const look = MAP_LOOK[mapId] || MAP_LOOK.rps_arena;
    this.scene.background = new THREE.Color(look.sky);
    this.scene.fog = new THREE.Fog(look.sky, look.fog[0], look.fog[1]);
    this.sun.intensity = look.sun;
    this.hemi.intensity = look.hemi;
    this.bloom.strength = mapId === 'neon_rooftops' ? 0.9 : 0.55;
    this.mapId = mapId;
    this.mode = 'game';
    // Warm up the shared models so first sight of a player doesn't hitch.
    return true;
  }

  preload(paths) { return Promise.all(paths.map((p) => loadGltf(p).catch(() => null))); }

  setCamera(x, y, z, yaw, pitch, fov) {
    const c = this.camera;
    c.position.set(x, y, z);
    c.rotation.set(pitch, -yaw, 0);
    if (Math.abs(c.fov - fov) > 1e-3) { c.fov = fov; c.updateProjectionMatrix(); }
    Object.assign(this.audio.listener, { x, y, z, yaw });
    this.sun.position.set(x + 30, y + 50, z + 20);
    this.sun.target.position.set(x, y, z);
    this.sun.target.updateMatrixWorld();
  }

  setGrayscale(on) { this.canvas.style.filter = on ? 'grayscale(1) brightness(0.85)' : ''; }

  // --------------------------------------------------------- viewmodel --
  // ------------------------------------------------- first-person skills --
  // Loads glb/fp_skills/<file>.glb with this character's arms on the grips.
  async _fpRig(file) {
    const [rig, arms] = await Promise.all([loadGltf(`glb/fp_skills/${file}.glb`), loadGltf(`glb/fp_arms/${this.vmChar}.glb`)]);
    const root = rig.scene.clone(true);
    const armRoot = arms.scene.clone(true);
    const gripR = findNode(root, 'grip_R'), gripL = findNode(root, 'grip_L');
    const armR = findNode(armRoot, 'arm_R'), armL = findNode(armRoot, 'arm_L');
    if (gripR && armR) { gripR.add(armR); armR.position.set(0, 0, 0); }
    if (gripL && armL) { gripL.add(armL); armL.position.set(0, 0, 0); }
    const mixer = new THREE.AnimationMixer(root);
    const actions = {};
    for (const clip of rig.animations) actions[clip.name] = mixer.clipAction(clip);
    this.mixers.add(mixer);
    return { root, mixer, actions, socket: findNode(root, 'item_socket') };
  }

  _dropRig(r) {
    if (!r) return;
    this.vmRoot.remove(r.root);
    this.mixers.delete(r.mixer);
  }

  _showGun(on) { if (this.vm) this.vm.root.visible = on; }

  // One-shot skill motion: 'throw' or 'place', with [item] (skill GLB) in hand.
  async vmSkill(anim, item) {
    if (this.vmModeRig || !this.vmChar) return;
    const token = (this._skillToken = {});
    const r = await this._fpRig(anim);
    if (token !== this._skillToken || this.vmModeRig) { this._dropRig(r); return; }
    if (item && r.socket) {
      loadGltf(item).then((g) => { const m = g.scene.clone(true); m.scale.setScalar(0.3); r.socket.add(m); }).catch(() => {});
    }
    this._dropRig(this.vmSkillRig);
    this.vmSkillRig = r;
    this.vmRoot.add(r.root);
    this._showGun(false);
    const a = r.actions[anim] || Object.values(r.actions)[0];
    if (a) { a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; a.reset().play(); }
    const dur = a ? a.getClip().duration : 0.5;
    setTimeout(() => {
      if (this.vmSkillRig !== r) return;
      this._dropRig(r);
      this.vmSkillRig = null;
      if (!this.vmModeRig) { this._showGun(true); this.vmPlay('draw', 1.6); }
    }, dur * 1000 + 60);
  }

  // Held weapon modes: 'shuriken', 'twin', 'guard' ('' = back to the gun).
  async vmMode(mode) {
    if (mode === (this.vmModeName || '')) return;
    this.vmModeName = mode;
    this._dropRig(this.vmModeRig);
    this.vmModeRig = null;
    const file = { shuriken: 'shuriken', twin: 'twin_blade', guard: 'shield' }[mode];
    if (!file || !this.vmChar) { this._showGun(true); return; }
    const r = await this._fpRig(file);
    if (this.vmModeName !== mode) { this._dropRig(r); return; }
    this._dropRig(this.vmSkillRig);
    this.vmSkillRig = null;
    this.vmModeRig = r;
    this.vmRoot.add(r.root);
    this._showGun(false);
    if (mode === 'guard' && r.actions.raise) {
      const a = r.actions.raise;
      a.setLoop(THREE.LoopOnce, 1);
      a.clampWhenFinished = true;
      a.play();
      setTimeout(() => { if (this.vmModeRig === r && r.actions.hold) { a.fadeOut(0.1); r.actions.hold.reset().fadeIn(0.1).play(); } },
        a.getClip().duration * 1000);
    } else if (r.actions.idle) {
      r.actions.idle.play();
    }
  }

  // Attack inside a held mode: shuriken throw, alternating blade slashes.
  vmModeAttack() {
    const r = this.vmModeRig;
    if (!r) return;
    let name = this.vmModeName === 'shuriken' ? 'throw' : (this._slashLeft = !this._slashLeft) ? 'slash_L' : 'slash_R';
    const a = r.actions[name];
    if (!a) return;
    a.setLoop(THREE.LoopOnce, 1);
    a.clampWhenFinished = false;
    if (r.actions.idle) r.actions.idle.stop();
    a.reset().play();
    setTimeout(() => { if (this.vmModeRig === r && r.actions.idle && !a.isRunning()) r.actions.idle.reset().play(); },
      a.getClip().duration * 1000 + 30);
  }

  async setViewmodel(charId, gunId, hold, sight, eye) {
    this.vmChar = charId;
    const token = (this._vmToken = {});
    if (DEBUG) console.log('[rps] setViewmodel', charId, gunId, JSON.stringify(hold), JSON.stringify(sight), eye);
    const [rig, arms] = await Promise.all([loadGltf(`glb/fp_rigs/${gunId}.glb`), loadGltf(`glb/fp_arms/${charId}.glb`)]);
    if (token !== this._vmToken) return;
    if (this.vm) { this.mixers.delete(this.vm.mixer); this.vmRoot.remove(this.vm.root); }
    const root = rig.scene.clone(true);
    const armRoot = arms.scene.clone(true);
    const gripR = findNode(root, 'grip_R'), gripL = findNode(root, 'grip_L');
    const armR = findNode(armRoot, 'arm_R'), armL = findNode(armRoot, 'arm_L');
    if (gripR && armR) { gripR.add(armR); armR.position.set(0, 0, 0); }
    if (gripL && armL) { gripL.add(armL); armL.position.set(0, 0, 0); }
    const fpRoot = findNode(root, 'fp_root') || root;
    // Optic bodies sit right on the line of sight; they fade out while aiming
    // so the zoomed view isn't a black disc (rifle scope, launcher sight).
    const optics = [];
    root.traverse((o) => {
      if (o.isMesh && /^(scope|turret_|sight_box|sight_lens|objective_lens)/.test(o.name)) {
        o.material = o.material.clone();
        o.material.userData.baseOpacity = o.material.opacity;
        optics.push(o);
      }
    });
    const mixer = new THREE.AnimationMixer(root);
    const actions = {};
    for (const clip of rig.animations) {
      const a = mixer.clipAction(clip);
      if (clip.name !== 'idle') { a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = false; }
      actions[clip.name] = a;
    }
    mixer.addEventListener('finished', () => {
      if (actions.idle && !actions.idle.isRunning()) actions.idle.reset().fadeIn(0.08).play();
    });
    if (actions.idle) actions.idle.play();
    this.mixers.add(mixer);
    this.vmRoot.add(root);
    if (this.vmModeRig || this.vmSkillRig) root.visible = false;
    this.vm = { root, fpRoot, mixer, actions, hold, sight, eye, gunId, optics, muzzle: findNode(root, 'muzzle') };
    if (DEBUG) {
      const box = new THREE.Box3().setFromObject(root);
      console.log('[rps] viewmodel', charId, gunId, 'optics', optics.map((o) => o.name).join('+'), 'clips', Object.keys(actions).join('/'), 'bounds',
        box.min.toArray().map((v) => v.toFixed(2)).join(','), box.max.toArray().map((v) => v.toFixed(2)).join(','));
    }
    this.vmPlay('draw', 1);
  }

  vmPlay(name, speed = 1) {
    const vm = this.vm;
    if (!vm || !vm.actions[name]) return;
    for (const [k, a] of Object.entries(vm.actions)) if (k !== name && k !== 'idle') a.stop();
    const a = vm.actions[name];
    if (vm.actions.idle) vm.actions.idle.stop();
    a.reset();
    a.timeScale = speed;
    a.play();
  }

  // Plays clip [name] stretched to last [seconds] (reload/draw follow the
  // sim's reloadTime/drawTime, not the clip's authored length).
  vmPlayFor(name, seconds) {
    const a = this.vm && this.vm.actions[name];
    if (!a) return;
    this.vmPlay(name, a.getClip().duration / Math.max(seconds, 0.05));
  }

  // Fire clip at max(1, clipLength * fireRate) (brief §6-9). [follow] is an
  // sfx played at [frac] of the clip (shotgun pump 35%, sniper bolt 30%).
  vmFire(fireRate, follow, frac) {
    const a = this.vm && this.vm.actions.fire;
    const dur = a ? a.getClip().duration : 0.2;
    const speed = Math.max(1, dur * fireRate);
    this.vmPlay('fire', speed);
    this.muzzleFlash();
    if (follow) setTimeout(() => this.audio.play(follow, 0.9), (dur * frac / speed) * 1000);
  }

  // adsT 0..1, bob in metres, kick = recoil pitch (rad) for a small visual tilt.
  vmPose(adsT, bobX, bobY, kick, visible) {
    this.vmVisible = visible;
    const vm = this.vm;
    if (!vm) return;
    // ADS offset = (0,0,-eye) - (hold + sight)  (catalog guns[].ads)
    const ox = -(vm.hold[0] + vm.sight[0]), oy = -(vm.hold[1] + vm.sight[1]), oz = -vm.eye - (vm.hold[2] + vm.sight[2]);
    const k = 1 - adsT * 0.85;
    vm.fpRoot.position.set(ox * adsT + bobX * k, oy * adsT + bobY * k, oz * adsT);
    vm.fpRoot.rotation.set(kick * 0.6 * k, 0, bobX * 0.5 * k);
    const f = 1 - THREE.MathUtils.smoothstep(adsT, 0.35, 0.85);
    for (const o of vm.optics) {
      o.visible = f > 0.02;
      o.material.opacity = o.material.userData.baseOpacity * f;
      o.material.transparent = f < 0.999 || o.material.userData.baseOpacity < 1;
      o.material.depthWrite = f > 0.5;
    }
    if (DEBUG && adsT > 0.99 && !this._adsLogged) {
      this._adsLogged = true;
      const cam = new THREE.Vector3();
      const hits = [];
      const ray = new THREE.Raycaster(cam, new THREE.Vector3(0, 0, -1), 0, 2);
      vm.root.updateMatrixWorld(true);
      for (const h of ray.intersectObject(vm.root, true)) hits.push(h.object.name + '@' + h.distance.toFixed(3));
      console.log('[rps] ads ray hits', hits.join(' '), 'fpRoot', vm.fpRoot.position.toArray().map((v) => v.toFixed(3)).join(','));
    }
  }

  // ------------------------------------------------------------ players --
  // Other players: full-body model + shared third-person clips
  // (glb/anims/third_person.glb). Two layers so you can shoot while walking:
  // lower body = locomotion, upper body = locomotion or fire/reload/hit.
  async _tpClips(charId, hipsRest) {
    this._tpBase ??= loadGltf('glb/anims/third_person.glb');
    this._tpByChar ??= new Map();
    if (this._tpByChar.has(charId)) return this._tpByChar.get(charId);
    const g = await this._tpBase;
    const LOWER = /^(hips|thigh_[LR]|shin_[LR]|foot_[LR])\./;
    const BASE_Y = 0.895; // hips rest of the reference skeleton (scroll)
    const k = hipsRest.y / BASE_Y;
    const lower = {}, upper = {};
    for (const clip of g.animations) {
      const tracks = clip.tracks.map((t) => {
        if (t.name !== 'hips.position') return t.clone();
        // Rescale the hips path to this character's leg length.
        const c = t.clone();
        const v = c.values;
        for (let i = 0; i < v.length; i += 3) {
          v[i] = hipsRest.x + v[i] * k;
          v[i + 1] = hipsRest.y + (v[i + 1] - BASE_Y) * k;
          v[i + 2] = hipsRest.z + v[i + 2] * k;
        }
        return c;
      });
      lower[clip.name] = new THREE.AnimationClip(clip.name + '_lo', clip.duration, tracks.filter((t) => LOWER.test(t.name)));
      upper[clip.name] = new THREE.AnimationClip(clip.name + '_up', clip.duration, tracks.filter((t) => !LOWER.test(t.name)));
    }
    const out = { lower, upper };
    this._tpByChar.set(charId, out);
    return out;
  }

  // Character + gun at rest pose with meshes merged per bone; shared by all
  // players using that combination (clones share geometry).
  async _playerProto(charId, gunId) {
    this._protos ??= new Map();
    const key = `${charId}/${gunId}`;
    if (!this._protos.has(key)) {
      this._protos.set(key, (async () => {
        const [ch, gun] = await Promise.all([loadGltf(`glb/characters/${charId}.glb`), loadGltf(`glb/guns/${gunId}.glb`)]);
        const model = ch.scene.clone(true);
        model.traverse((o) => { if (o.isMesh) o.castShadow = true; });
        const socket = findNode(model, 'weapon_socket_R');
        if (socket) socket.add(gun.scene.clone(true));
        const merged = mergeMeshes(model, nearestNonMesh);
        if (DEBUG) console.log('[rps] player merge', key, merged);
        return model;
      })());
    }
    return this._protos.get(key);
  }

  async _buildPlayer(p, charId, gunId) {
    const proto = await this._playerProto(charId, gunId);
    if (p.charId !== charId || p.gunId !== gunId || !this.players.has(p.id)) return;
    if (p.model) p.root.remove(p.model);
    if (p.mixer) this.mixers.delete(p.mixer);
    const model = proto.clone(true);
    const socket = findNode(model, 'weapon_socket_R');
    p.muzzle = socket ? findNode(socket, 'muzzle') : null;
    p.bones = { chest: findNode(model, 'chest'), head: findNode(model, 'head') };
    const hips = findNode(model, 'hips');
    p.model = model;
    p.root.add(model);
    const clips = await this._tpClips(charId, hips ? hips.position.clone() : new THREE.Vector3(0, 0.9, 0));
    if (p.model !== model) return;
    const mixer = new THREE.AnimationMixer(model);
    p.mixer = mixer;
    p.lo = {};
    p.up = {};
    for (const n of Object.keys(clips.lower)) {
      p.lo[n] = mixer.clipAction(clips.lower[n]);
      p.up[n] = mixer.clipAction(clips.upper[n]);
      if (['fire', 'reload', 'hit', 'jump'].includes(n)) {
        for (const a of [p.lo[n], p.up[n]]) { a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; }
      }
    }
    p.loState = p.upState = '';
    p.overrideT = 0;
    this.mixers.add(mixer);
  }

  _fade(map, from, to, t = 0.15) {
    const next = map[to];
    if (!next) return;
    const prev = map[from];
    next.reset().setEffectiveWeight(1).fadeIn(t).play();
    if (prev && prev !== next) prev.fadeOut(t);
  }

  // Trigger an upper-body action on a remote player: fire, reload, hit.
  playerAction(id, name) {
    const p = this.players.get(id);
    if (!p || !p.up || !p.up[name]) return;
    this._fade(p.up, p.upState, name, 0.05);
    p.upState = name;
    p.overrideT = p.up[name].getClip().duration;
    if (name === 'fire' && p.muzzle) this._flashAt(p.muzzle, 0.6);
  }

  // Muzzle world position of a remote player's gun (tracer start), or null.
  playerMuzzle(id) {
    const p = this.players.get(id);
    if (!p || !p.muzzle || !p.root.visible) return null;
    const v = new THREE.Vector3();
    p.muzzle.getWorldPosition(v);
    return [v.x, v.y, v.z];
  }

  // aura: 0 none, 1 shield, 2 disabled (root/stun/sleep), 3 buffed, 4 invulnerable, 5 slowed
  setPlayer(id, charId, gunId, team, friendly, x, y, z, yaw, pitch, speed, alive, crouch, revealed = false, aura = 0, ball = '',
    onGround = true) {
    let p = this.players.get(id);
    if (!p) {
      p = { id, root: new THREE.Group(), model: null, charId: '', gunId: '', last: null };
      const tag = new THREE.Mesh(new THREE.OctahedronGeometry(0.09),
        new THREE.MeshBasicMaterial({ color: 0x4d8cf0 }));
      tag.position.y = 2.25;
      p.tag = tag;
      p.root.add(tag);
      this.dynamic.add(p.root);
      this.players.set(id, p);
    }
    if (p.charId !== charId || p.gunId !== gunId) {
      p.charId = charId;
      p.gunId = gunId;
      this._buildPlayer(p, charId, gunId);
    }
    p.tag.visible = friendly || revealed;
    p.tag.material.color.set(revealed && !friendly ? 0xff3b3b : (team === 0 ? 0xff8a2a : 0x4d8cf0));
    // Revealed enemies: marker visible through walls.
    p.tag.material.depthTest = !revealed;
    p.tag.renderOrder = revealed ? 10 : 0;
    p.tag.scale.setScalar(revealed && !friendly ? 1.8 : 1);
    p.root.visible = alive;
    // Movement direction relative to facing, from the position change.
    const now = performance.now();
    let fwd = 0, side = 0;
    if (p.last) {
      const dt = Math.max((now - p.last.t) / 1000, 1e-3);
      const vx = (x - p.last.x) / dt, vz = (z - p.last.z) / dt;
      fwd = vx * Math.sin(yaw) - vz * Math.cos(yaw);
      side = vx * Math.cos(yaw) + vz * Math.sin(yaw);
    }
    p.last = { x, z, t: now };
    p.root.position.set(x, y, z);
    if (!p.aura) {
      p.aura = new THREE.Mesh(new THREE.TorusGeometry(0.55, 0.05, 8, 32),
        new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.8, depthWrite: false }));
      p.aura.rotation.x = Math.PI / 2;
      p.aura.position.y = 0.1;
      p.root.add(p.aura);
    }
    p.aura.visible = aura > 0;
    if (aura > 0) {
      p.aura.material.color.set([0, 0x6fc3ff, 0xb46bff, 0xffc04a, 0xffffff, 0x4aa8ff][aura]);
      p.aura.position.y = aura === 2 ? 1.9 : 0.1 + 0.05 * Math.sin(now / 200);
    }
    // Rolling (crate roll): show the skill model instead of the body.
    if (ball !== (p.ballFile || '')) {
      if (p.ball) { p.root.remove(p.ball); p.ball = null; }
      p.ballFile = ball;
      if (ball) loadGltf(ball).then((g) => { if (p.ballFile === ball) { p.ball = g.scene.clone(true); p.root.add(p.ball); } });
    }
    if (p.model) p.model.visible = !ball;
    if (p.ball) p.ball.rotation.x += speed * 0.03;
    p.root.rotation.y = Math.PI - yaw;
    p.pitch = pitch;
    if (!p.lo) return;
    // Pick the locomotion clip.
    let st, rate = 1;
    if (!onGround) st = 'jump';
    else if (crouch) { st = speed > 0.5 ? 'crouch_walk' : 'crouch_idle'; rate = Math.max(0.6, speed / 2.2); }
    else if (speed < 0.4) st = 'idle_gun';
    else if (Math.abs(side) > Math.abs(fwd) * 1.2) { st = side < 0 ? 'strafe_L' : 'strafe_R'; rate = speed / 3.5; }
    else if (fwd < -0.3) { st = 'back'; rate = speed / 3; }
    else if (speed > 4) { st = 'run'; rate = speed / 5.6; }
    else { st = 'walk'; rate = speed / 2.6; }
    rate = Math.min(Math.max(rate, 0.5), 1.6);
    if (st !== p.loState) {
      this._fade(p.lo, p.loState, st);
      p.loState = st;
    }
    p.lo[st].timeScale = st === 'jump' ? 1 : rate;
    // Upper body follows locomotion unless fire/reload/hit is playing.
    if (p.overrideT > 0) {
      p.overrideT -= 1 / 60;
    } else if (p.upState !== st) {
      this._fade(p.up, p.upState, st);
      p.upState = st;
    }
    if (p.up[st]) p.up[st].timeScale = p.lo[st].timeScale;
  }

  // Aim pitch on top of the animation (mixer overwrites bones every frame).
  _applyAim() {
    for (const p of this.players.values()) {
      if (!p.bones || !p.root.visible) continue;
      const pitch = p.pitch || 0;
      if (p.bones.chest) p.bones.chest.rotateX(-pitch * 0.55);
      if (p.bones.head) p.bones.head.rotateX(-pitch * 0.35);
    }
  }

  removePlayer(id) {
    const p = this.players.get(id);
    if (!p) return;
    if (p.mixer) this.mixers.delete(p.mixer);
    this.dynamic.remove(p.root);
    this.players.delete(id);
  }

  clearPlayers() {
    for (const id of [...this.players.keys()]) this.removePlayer(id);
    for (const id of [...this.deployables.keys()]) this._removeDep(id);
    for (const [id, m] of this.projectiles) { this.dynamic.remove(m); this.projectiles.delete(id); }
  }

  // ------------------------------------------------------- deployables --
  // Skill objects in the world. [file] is the skill GLB ('' = none);
  // [shape]: 0 model only, 1 ground area ring, 2 smoke ball, 3 dome, 4 wall.
  setDeployable(id, file, shape, x, y, z, yaw, radius, team, friendly, hpFrac) {
    let d = this.deployables.get(id);
    if (!d) {
      d = { root: new THREE.Group(), area: null };
      const col = friendly ? 0x4dc9ff : 0xff5a4a;
      if (file) {
        loadGltf(file).then((g) => { if (this.deployables.get(id) === d) d.root.add(g.scene.clone(true)); }).catch(() => {});
      }
      if (shape === 1) {
        d.area = new THREE.Mesh(new THREE.RingGeometry(0.92, 1, 64),
          new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false }));
        d.area.rotation.x = -Math.PI / 2;
        d.area.position.y = 0.06;
        const fill = new THREE.Mesh(new THREE.CircleGeometry(1, 48),
          new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0.12, side: THREE.DoubleSide, depthWrite: false }));
        fill.rotation.x = -Math.PI / 2;
        fill.position.y = 0.05;
        d.fill = fill;
        this.dynamic.add(d.area, fill);
      } else if (shape === 2) {
        d.area = new THREE.Group();
        loadGltf('glb/fx/smoke_cloud.glb').then((g) => d.area.add(g.scene.clone(true))).catch(() => {});
        this.dynamic.add(d.area);
      } else if (shape === 3) {
        d.area = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2),
          new THREE.MeshStandardMaterial({ color: 0xc8a06a, transparent: true, opacity: 0.35, depthWrite: false, side: THREE.DoubleSide }));
        this.dynamic.add(d.area);
      } else if (shape === 4) {
        // Ink wall: 1 m tiles along the wall, 3 m tall model stretched to 8 m.
        d.area = new THREE.Group();
        const n = Math.max(1, Math.round(radius * 2));
        loadGltf('glb/fx/ink_wall.glb').then((g) => {
          for (let i = 0; i < n; i++) {
            const t = g.scene.clone(true);
            t.position.x = i - n / 2 + 0.5;
            d.area.add(t);
          }
        }).catch(() => {});
        this.dynamic.add(d.area);
      }
      this.dynamic.add(d.root);
      this.deployables.set(id, d);
    }
    d.seen = true;
    d.root.position.set(x, y, z);
    d.root.rotation.y = Math.PI - yaw;
    if (d.area) {
      if (shape === 1) { d.area.position.set(x, y + 0.06, z); d.area.scale.setScalar(radius); d.fill.position.set(x, y + 0.05, z); d.fill.scale.setScalar(radius); }
      if (shape === 2) { d.area.position.set(x, y - radius * 0.6, z); d.area.scale.setScalar(Math.max(radius, 0.1)); }
      if (shape === 3) { d.area.position.set(x, y, z); d.area.scale.setScalar(radius); }
      if (shape === 4) {
        d.area.position.set(x, y, z);
        d.area.rotation.y = Math.PI / 2 - yaw; // tile X axis along the facing
        d.area.scale.set(1, 8 / 3, 1);
      }
    }
  }

  // Remove deployables not updated since the last prune.
  pruneDeployables() {
    for (const [id, d] of this.deployables) {
      if (!d.seen) this._removeDep(id);
      else d.seen = false;
    }
  }

  _removeDep(id) {
    const d = this.deployables.get(id);
    if (!d) return;
    this.dynamic.remove(d.root);
    if (d.area) this.dynamic.remove(d.area);
    if (d.fill) this.dynamic.remove(d.fill);
    this.deployables.delete(id);
  }

  // Projectile with an optional skill model ('' = glowing ball).
  setProjectile(id, file, x, y, z) {
    let m = this.projectiles.get(id);
    if (!m) {
      m = new THREE.Group();
      if (!file) {
        m.add(new THREE.Mesh(new THREE.SphereGeometry(0.12, 10, 8),
          new THREE.MeshStandardMaterial({ color: 0xffb347, emissive: 0xff7a1a, emissiveIntensity: 4 })));
      } else {
        loadGltf(file).then((g) => { const c = g.scene.clone(true); c.scale.setScalar(0.6); m.add(c); }).catch(() => {});
      }
      this.dynamic.add(m);
      this.projectiles.set(id, m);
    }
    m.userData.seen = true;
    const dx = x - m.position.x, dz = z - m.position.z;
    if (dx * dx + dz * dz > 1e-6) m.rotation.y = Math.atan2(dx, dz);
    m.position.set(x, y, z);
  }

  pruneProjectiles() {
    for (const [id, m] of this.projectiles) {
      if (!m.userData.seen) { this.dynamic.remove(m); this.projectiles.delete(id); } else m.userData.seen = false;
    }
  }

  // Heal beams: flat [x1, y1, z1, x2, y2, z2, ...]
  setLinks(flat) {
    this.beams ??= [];
    const n = Math.floor(flat.length / 6);
    while (this.beams.length < n) {
      const holder = new THREE.Group();
      loadGltf('glb/fx/heal_beam.glb').then((g) => holder.add(g.scene.clone(true))).catch(() => {});
      this.dynamic.add(holder);
      this.beams.push(holder);
    }
    for (let i = 0; i < this.beams.length; i++) {
      const b = this.beams[i];
      b.visible = i < n;
      if (i >= n) continue;
      const a = new THREE.Vector3(flat[i * 6], flat[i * 6 + 1], flat[i * 6 + 2]);
      const c = new THREE.Vector3(flat[i * 6 + 3], flat[i * 6 + 4], flat[i * 6 + 5]);
      b.position.copy(a);
      b.lookAt(c);
      b.scale.set(1, 1, Math.max(0.1, a.distanceTo(c)));
    }
  }

  // Capture zone: ground ring + soft light pillar in the owner's colour.
  setCaptureZone(x, y, z, r, color, contested) {
    if (!this.zone) {
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.94, 1, 96),
        new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.8, side: THREE.DoubleSide, depthWrite: false }));
      ring.rotation.x = -Math.PI / 2;
      const fill = new THREE.Mesh(new THREE.CircleGeometry(1, 64),
        new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.08, side: THREE.DoubleSide, depthWrite: false }));
      fill.rotation.x = -Math.PI / 2;
      const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 30, 12, 1, true),
        new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.18, depthWrite: false, side: THREE.DoubleSide }));
      this.zone = { ring, fill, beam };
      this.dynamic.add(ring, fill, beam);
    }
    const zn = this.zone;
    if (!zn.flag) {
      zn.flag = new THREE.Group();
      this.dynamic.add(zn.flag);
      loadGltf('glb/fx/capture_flag.glb').then((g) => {
        const f = g.scene.clone(true);
        zn.flagMats = [];
        f.traverse((o) => {
          if (o.isMesh && o.material && /team_(flag|glow|light)/.test(o.material.name)) {
            o.material = o.material.clone();
            zn.flagMats.push(o.material);
          }
        });
        zn.flag.add(f);
        const clip = g.animations.find((a) => a.name === 'wave');
        if (clip) { zn.mixer = new THREE.AnimationMixer(f); zn.mixer.clipAction(clip).play(); this.mixers.add(zn.mixer); }
      }).catch(() => {});
    }
    zn.flag.position.set(x, y, z);
    for (const m of zn.flagMats || []) {
      m.color.set(color);
      if (m.emissive) m.emissive.set(color);
    }
    const pulse = contested ? 0.5 + 0.5 * Math.sin(performance.now() / 120) : 1;
    for (const m of [zn.ring, zn.fill, zn.beam]) m.material.color.set(color);
    zn.ring.material.opacity = 0.85 * pulse;
    zn.ring.position.set(x, y + 0.05, z);
    zn.ring.scale.setScalar(r);
    zn.fill.position.set(x, y + 0.04, z);
    zn.fill.scale.setScalar(r);
    zn.beam.position.set(x, y + 15, z);
  }

  // ----------------------------------------------------------------- fx --
  // Bullet trail. [from]: 'vm' = local viewmodel muzzle, a player id = that
  // player's gun muzzle, otherwise (ox,oy,oz).
  tracer(ox, oy, oz, ex, ey, ez, hit, from = -1) {
    let o = null;
    if (from === 'vm') o = this._vmMuzzleWorld();
    else if (from >= 0) o = this.playerMuzzle(from);
    const a = o ? new THREE.Vector3(o[0], o[1], o[2]) : new THREE.Vector3(ox, oy - 0.08, oz);
    const geo = new THREE.BufferGeometry().setFromPoints([a, new THREE.Vector3(ex, ey, ez)]);
    const mat = new THREE.LineBasicMaterial({ color: 0xffe28a, transparent: true, opacity: 0.85 });
    const line = new THREE.Line(geo, mat);
    this.dynamic.add(line);
    this.fx.push({ obj: line, life: 0.07, max: 0.07, fade: mat });
    if (hit === 0) {
      // Wall: impact model, +Z = surface normal (we face it back at the shooter).
      loadGltf('glb/fx/impact.glb').then((g) => {
        const m = g.scene.clone(true);
        m.position.set(ex, ey, ez);
        m.lookAt(a);
        this.dynamic.add(m);
        this.fx.push({ obj: m, life: 0.25, max: 0.25 });
      }).catch(() => {});
    } else if (hit > 0) {
      const spark = new THREE.Mesh(new THREE.SphereGeometry(0.07, 6, 5),
        new THREE.MeshBasicMaterial({ color: 0xff5a5a, transparent: true }));
      spark.position.set(ex, ey, ez);
      this.dynamic.add(spark);
      this.fx.push({ obj: spark, life: 0.15, max: 0.15, fade: spark.material, grow: 1.5 });
    }
  }

  _vmMuzzleWorld() {
    const m = this.vm && this.vm.muzzle;
    if (!m) return null;
    this.vm.root.updateMatrixWorld(true);
    const v = new THREE.Vector3();
    m.getWorldPosition(v); // viewmodel space == camera space (vm camera sits at the origin)
    this.camera.updateMatrixWorld();
    v.applyMatrix4(this.camera.matrixWorld);
    return [v.x, v.y, v.z];
  }

  // Muzzle flash model on a muzzle node, random roll, very short.
  _flashAt(node, scale = 1) {
    loadGltf('glb/fx/muzzle_flash.glb').then((g) => {
      const f = g.scene.clone(true);
      f.scale.setScalar(scale);
      f.rotation.z = Math.random() * Math.PI * 2;
      node.add(f);
      this.fx.push({ obj: f, life: 0.05, max: 0.05, parent: node });
    }).catch(() => {});
  }

  muzzleFlash() {
    if (!this.vm) return;
    const l = new THREE.PointLight(0xffc56b, 6, 3);
    l.position.set(0.1, -0.05, -0.6);
    this.vmScene.add(l);
    this.fx.push({ obj: l, life: 0.05, max: 0.05, scene: this.vmScene });
    if (this.vm.muzzle) this._flashAt(this.vm.muzzle);
  }

  explosion(x, y, z, r) {
    const light = new THREE.PointLight(0xff9a40, 30, r * 4);
    light.position.set(x, y + 0.5, z);
    this.dynamic.add(light);
    this.fx.push({ obj: light, life: 0.3, max: 0.3 });
    loadGltf('glb/fx/explosion.glb').then((g) => {
      const m = g.scene.clone(true);
      m.position.set(x, y, z);
      m.scale.setScalar(Math.max(0.4, r / 1.6));
      this.dynamic.add(m);
      const mixer = new THREE.AnimationMixer(m);
      const clip = g.animations.find((a) => a.name === 'boom') || g.animations[0];
      if (clip) { const a = mixer.clipAction(clip); a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; a.play(); }
      this.mixers.add(mixer);
      this.fx.push({ obj: m, life: 0.65, max: 0.65, mixer });
    }).catch(() => {});
  }

  burst(x, y, z, color, size = 0.6, life = 0.35) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 12),
      new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.7, depthWrite: false }));
    m.position.set(x, y, z);
    m.scale.setScalar(size * 0.3);
    this.dynamic.add(m);
    this.fx.push({ obj: m, life, max: life, fade: m.material, to: size });
  }

  // kind: 'blink' (a -> b), 'rewind' (a -> b), 'reveal' (a = point, r = radius), 'stick'
  async skillFx(kind, ax, ay, az, bx, by, bz, r) {
    if (kind === 'blink') {
      this.burst(ax, ay + 1, az, 0xbfe6ff, 0.8);
      this.burst(bx, by + 1, bz, 0xbfe6ff, 0.8);
      const g = await loadGltf('glb/skills/pebble/gravel_blink.glb');
      const trail = g.scene.clone(true);
      const len = Math.hypot(bx - ax, bz - az);
      trail.position.set(ax, Math.min(ay, by) + 0.05, az);
      trail.rotation.y = Math.atan2(bx - ax, bz - az);
      trail.scale.set(1, 1, Math.max(0.3, len / 1.65));
      this.dynamic.add(trail);
      this.fx.push({ obj: trail, life: 0.9, max: 0.9 });
    } else if (kind === 'rewind') {
      this.burst(ax, ay + 1, az, 0x7fe8ff, 1.0, 0.5);
      this.burst(bx, by + 1, bz, 0x7fe8ff, 1.0, 0.5);
      const g = await loadGltf('glb/skills/pebble/rewind.glb');
      const glass = g.scene.clone(true);
      glass.position.set(bx, by, bz);
      this.dynamic.add(glass);
      this.fx.push({ obj: glass, life: 1.2, max: 1.2 });
    } else if (kind === 'reveal') {
      const ring = new THREE.Mesh(new THREE.TorusGeometry(1, 0.06, 8, 64),
        new THREE.MeshBasicMaterial({ color: 0xffa040, transparent: true, opacity: 0.9, depthWrite: false }));
      ring.rotation.x = Math.PI / 2;
      ring.position.set(ax, ay + 0.3, az);
      ring.scale.setScalar(0.3);
      this.dynamic.add(ring);
      this.fx.push({ obj: ring, life: 0.9, max: 0.9, fade: ring.material, to: r });
    } else if (kind === 'stick') {
      this.burst(ax, ay, az, 0xff5a3a, 0.4, 0.25);
    }
  }

  // Floating damage number above a victim. Hits on the same victim within
  // 0.35 s merge (shotgun pellets, damage over time).
  // kind: 0 body, 1 head, 2 shield
  damageNumber(victimId, x, y, z, amount, kind) {
    this.dmgNums ??= new Map(); // latest number per victim (for merging)
    this.dmgAll ??= new Set(); // every number still on screen
    const now = performance.now();
    let n = this.dmgNums.get(victimId);
    if (n && now - n.born < 350 && n.kind === kind) {
      n.amount += amount;
      n.life = n.max;
      n.born = now;
      this._drawDamage(n);
      return;
    }
    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 96;
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true }));
    sprite.renderOrder = 20;
    sprite.position.set(x + (Math.random() - 0.5) * 0.4, y, z + (Math.random() - 0.5) * 0.4);
    this.dynamic.add(sprite);
    n = { sprite, canvas, tex, amount, kind, born: now, life: 0.9, max: 0.9, y0: sprite.position.y };
    // The previous number for this victim keeps fading out on its own (it
    // used to be dropped from the map here and stayed on screen forever).
    this.dmgNums.set(victimId, n);
    this.dmgAll.add(n);
    this._drawDamage(n);
  }

  _drawDamage(n) {
    const c = n.canvas.getContext('2d');
    c.clearRect(0, 0, 256, 96);
    c.font = `900 ${n.kind === 1 ? 64 : 52}px "Noto Sans KR", sans-serif`;
    c.textAlign = 'center';
    c.textBaseline = 'middle';
    c.lineWidth = 8;
    c.strokeStyle = 'rgba(0,0,0,0.75)';
    const t = String(Math.max(1, Math.round(n.amount)));
    c.strokeText(t, 128, 50);
    c.fillStyle = n.kind === 1 ? '#ffd23f' : n.kind === 2 ? '#7cc8ff' : '#ffffff';
    c.fillText(t, 128, 50);
    n.tex.needsUpdate = true;
  }

  _updateDamage(dt) {
    if (!this.dmgAll) return;
    for (const n of this.dmgAll) {
      n.life -= dt;
      const t = 1 - n.life / n.max;
      n.sprite.position.y = n.y0 + t * 0.7;
      n.sprite.material.opacity = Math.min(1, n.life / 0.3);
      // Constant on-screen size regardless of distance.
      const d = n.sprite.position.distanceTo(this.camera.position);
      const k = d * 0.055 * (n.kind === 1 ? 1.2 : 1);
      n.sprite.scale.set(k * 2.67, k, 1);
      if (n.life <= 0) {
        this.dynamic.remove(n.sprite);
        n.tex.dispose();
        n.sprite.material.dispose();
        this.dmgAll.delete(n);
        for (const [id, m] of this.dmgNums) if (m === n) this.dmgNums.delete(id);
      }
    }
  }

  // Victory / defeat effect floating in front of the camera.
  async matchEnd(won) {
    const g = await loadGltf(`glb/fx/${won ? 'match_victory' : 'match_defeat'}.glb`);
    const m = g.scene.clone(true);
    const f = new THREE.Vector3();
    this.camera.getWorldDirection(f);
    f.y = 0;
    f.normalize();
    m.position.copy(this.camera.position).addScaledVector(f, 3.5);
    m.position.y -= 1.2;
    m.lookAt(this.camera.position.x, m.position.y, this.camera.position.z);
    this.dynamic.add(m);
    const mixer = new THREE.AnimationMixer(m);
    const clip = g.animations.find((a) => a.name === (won ? 'victory' : 'defeat')) || g.animations[0];
    if (clip) { const a = mixer.clipAction(clip); a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; a.play(); }
    this.mixers.add(mixer);
    this.fx.push({ obj: m, life: 6, max: 6, mixer });
    this.audio.play(won ? 'match_victory' : 'match_defeat', 0.9);
  }

  async killBadge(kind) {
    const g = await loadGltf(`glb/fx/${kind}.glb`);
    const b = g.scene.clone(true);
    // Small, bottom centre of the screen (brief §5: distance 0.6, scale 0.32).
    b.position.set(0, -0.2, -0.6);
    b.scale.setScalar(0.32 * 0.25);
    this.badges.add(b);
    const mixer = new THREE.AnimationMixer(b);
    const clip = g.animations.find((a) => a.name === 'pop') || g.animations[0];
    if (clip) { const a = mixer.clipAction(clip); a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; a.play(); }
    this.mixers.add(mixer);
    this.fx.push({ obj: b, life: 1.3, max: 1.3, scene: this.badges, mixer });
  }

  async deathGhost(kind, x, y, z, yawToCam) {
    const g = await loadGltf(`glb/fx/${kind}.glb`);
    const ghost = g.scene.clone(true);
    ghost.position.set(x, y, z);
    ghost.rotation.y = yawToCam;
    this.dynamic.add(ghost);
    const mixer = new THREE.AnimationMixer(ghost);
    const clip = g.animations.find((a) => a.name === 'death') || g.animations[0];
    if (clip) { const a = mixer.clipAction(clip); a.setLoop(THREE.LoopOnce, 1); a.clampWhenFinished = true; a.play(); }
    this.mixers.add(mixer);
    this.fx.push({ obj: ghost, life: 2.8, max: 2.8, mixer });
  }

  _updateFx(dt) {
    for (let i = this.fx.length - 1; i >= 0; i--) {
      const f = this.fx[i];
      f.life -= dt;
      const t = 1 - Math.max(f.life, 0) / f.max;
      if (f.fade) f.fade.opacity = Math.max(0, 1 - t) * (f.fade.userData.o0 ??= f.fade.opacity);
      if (f.grow) f.obj.scale.setScalar(1 + t * f.grow);
      if (f.to) f.obj.scale.setScalar(0.3 + (f.to - 0.3) * Math.min(1, t * 2.5));
      if (f.life <= 0) {
        if (f.parent) f.parent.remove(f.obj);
        else (f.scene || this.dynamic).remove(f.obj);
        if (f.mixer) this.mixers.delete(f.mixer);
        this.fx.splice(i, 1);
      }
    }
  }

  clearFx() {
    if (this.zone) {
      for (const k of ['ring', 'fill', 'beam', 'flag']) if (this.zone[k]) this.dynamic.remove(this.zone[k]);
      if (this.zone.mixer) this.mixers.delete(this.zone.mixer);
      this.zone = null;
    }
    if (this.beams) { for (const b of this.beams) this.dynamic.remove(b); this.beams = []; }
    for (const f of this.fx) { (f.scene || this.dynamic).remove(f.obj); if (f.mixer) this.mixers.delete(f.mixer); }
    this.fx.length = 0;
    for (const [id, m] of this.projectiles) { this.dynamic.remove(m); this.projectiles.delete(id); }
  }
}

window.rpsEngine = new Engine();
window.dispatchEvent(new Event('rps-engine-ready'));
