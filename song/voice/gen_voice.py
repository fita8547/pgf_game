"""Agent voice lines -> mp3 with Microsoft Edge neural TTS (edge-tts).

    python -m pip install edge-tts
    python song/voice/gen_voice.py            # only missing files
    python song/voice/gen_voice.py --force    # regenerate everything

Reads song/voice/voice_lines.json (copied from new-modeling/voice) and writes
song/voice/<agent>/<id>.mp3. A recorded file with the same name simply
replaces the TTS one. Korean has only 3 neural voices, so characters are told
apart by pitch and speed (VOICES below).
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


def jobs(data):
    for agent, a in data["agents"].items():
        for lines in a["lines"].values():
            for l in lines:
                yield agent, l["id"], l["text"]
    for it in data.get("interactions", []):
        for l in it["lines"]:
            yield l["agent"], l["id"], l["text"]


async def main(force):
    data = json.loads((HERE / "voice_lines.json").read_text(encoding="utf-8"))
    todo = []
    for agent, lid, text in jobs(data):
        out = HERE / agent / f"{lid}.mp3"
        if out.exists() and out.stat().st_size > 0 and not force:
            continue
        todo.append((agent, lid, text, out))
    print(f"{len(todo)} lines to generate")
    sem = asyncio.Semaphore(6)
    done = 0
    failed = []

    async def one(agent, lid, text, out):
        nonlocal done
        voice, rate, pitch = VOICES[agent]
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
