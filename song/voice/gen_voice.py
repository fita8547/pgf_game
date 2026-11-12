"""Agent voice lines -> mp3 with Microsoft Edge neural TTS (edge-tts).

    python -m pip install edge-tts
    python song/voice/gen_voice.py            # only missing files
    python song/voice/gen_voice.py --force    # regenerate everything

Reads song/voice/voice_lines.json (copied from new-modeling/voice) and writes
song/voice/<agent>/<id>.mp3 (Korean) and song/voice/en/<agent>/<id>.mp3
(English, text from voice_lines_en.txt, merged into the json as "en"). A
recorded file with the same name simply replaces the TTS one. Korean has only
3 neural voices, so characters are told apart by pitch and speed (VOICES).
"""
import asyncio
import json
import pathlib
import sys

import edge_tts

HERE = pathlib.Path(__file__).resolve().parent

# agent -> (voice, rate, pitch)
VOICES = {
    "boulder":   ("ko-KR-InJoonNeural", "-12%", "-12Hz"),  # orc, deep and slow
    "cardboard": ("ko-KR-HyunsuMultilingualNeural", "+8%", "-2Hz"),  # cheerful courier
    "shear":     ("ko-KR-SunHiNeural", "+5%", "-10Hz"),  # rough big sister
    "origami":   ("ko-KR-SunHiNeural", "-8%", "-6Hz"),   # calm, low
    "pebble":    ("ko-KR-SunHiNeural", "+12%", "+12Hz"),  # small, bright
    "snip":      ("ko-KR-HyunsuMultilingualNeural", "-2%", "-8Hz"),  # dry, cold
    "gem":       ("ko-KR-SunHiNeural", "+4%", "+6Hz"),   # kind, sparkly
    "needle":    ("ko-KR-SunHiNeural", "-4%", "-3Hz"),   # deadpan doctor
    "scroll":    ("ko-KR-InJoonNeural", "-15%", "-6Hz"),  # old scholar
    "inkwell":   ("ko-KR-SunHiNeural", "-12%", "+2Hz"),  # lazy cat painter
    "quake":     ("ko-KR-HyunsuMultilingualNeural", "+12%", "+4Hz"),  # loud smith
    "staple":    ("ko-KR-InJoonNeural", "-5%", "-20Hz"),  # robot, flat
}


# English: many more voices, so each agent gets their own.
VOICES_EN = {
    "boulder":   ("en-US-ChristopherNeural", "-10%", "-10Hz"),
    "cardboard": ("en-US-GuyNeural", "+5%", "+0Hz"),
    "shear":     ("en-GB-SoniaNeural", "+3%", "-6Hz"),
    "origami":   ("en-US-AvaNeural", "-8%", "-4Hz"),
    "pebble":    ("en-US-AnaNeural", "+8%", "+4Hz"),
    "snip":      ("en-GB-RyanNeural", "-2%", "-6Hz"),
    "gem":       ("en-US-JennyNeural", "+4%", "+4Hz"),
    "needle":    ("en-US-MichelleNeural", "-4%", "-2Hz"),
    "scroll":    ("en-GB-ThomasNeural", "-12%", "-4Hz"),
    "inkwell":   ("en-GB-LibbyNeural", "-10%", "+0Hz"),
    "quake":     ("en-US-EricNeural", "+10%", "+2Hz"),
    "staple":    ("en-US-SteffanNeural", "-5%", "-15Hz"),
}


def merge_en(data):
    """voice_lines_en.txt ("id | text") -> line["en"]; returns missing ids."""
    en = {}
    src = HERE / "voice_lines_en.txt"
    if src.exists():
        for raw in src.read_text(encoding="utf-8").splitlines():
            raw = raw.strip()
            if raw and not raw.startswith("#") and " | " in raw:
                k, t = raw.split(" | ", 1)
                en[k] = t
    missing = []
    for _, l in all_lines(data):
        if l["id"] in en:
            l["en"] = en[l["id"]]
        else:
            missing.append(l["id"])
    return missing


def all_lines(data):
    for agent, a in data["agents"].items():
        for lines in a["lines"].values():
            for l in lines:
                yield agent, l
    for it in data.get("interactions", []):
        for l in it["lines"]:
            yield l["agent"], l


def jobs(data):
    for agent, l in all_lines(data):
        yield agent, l["id"], l["text"], VOICES[agent], HERE / agent / f"{l['id']}.mp3"
        if l.get("en"):
            yield agent, l["id"], l["en"], VOICES_EN[agent], HERE / "en" / agent / f"{l['id']}.mp3"


async def main(force):
    path = HERE / "voice_lines.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    missing = merge_en(data)
    if missing:
        print(f"{len(missing)} lines without English text, e.g. {missing[:3]}")
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    todo = []
    for agent, lid, text, voice, out in jobs(data):
        if out.exists() and out.stat().st_size > 0 and not force:
            continue
        todo.append((lid, text, voice, out))
    print(f"{len(todo)} lines to generate")
    sem = asyncio.Semaphore(6)
    done = 0
    failed = []

    async def one(lid, text, spec, out):
        nonlocal done
        voice, rate, pitch = spec
        out.parent.mkdir(parents=True, exist_ok=True)
        async with sem:
            for attempt in range(3):
                try:
                    await edge_tts.Communicate(text, voice, rate=rate, pitch=pitch).save(str(out))
                    break
                except Exception as e:  # network hiccups: retry
                    if attempt == 2:
                        failed.append((lid, str(e)))
                    await asyncio.sleep(1 + attempt)
        done += 1
        if done % 50 == 0:
            print(f"  {done}/{len(todo)}")

    await asyncio.gather(*(one(*j) for j in todo))
    print(f"done, {len(failed)} failed")
    for f in failed:
        print("  failed", *f)


if __name__ == "__main__":
    asyncio.run(main("--force" in sys.argv))
