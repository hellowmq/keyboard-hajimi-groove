#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLAN_PATH = ROOT / "Samples" / "hajimi-local" / "segment-plan.json"
THEME_PATH = ROOT / "Themes" / "shortcut-local-drops.json"


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def clip_entry(segment: dict) -> dict:
    return {
        "id": segment["id"],
        "title": segment["title"],
        "artist": segment["source"].removesuffix(".WAV"),
        "filePath": segment["output"],
        "startTime": 0,
        "duration": segment["duration"],
        "volume": segment.get("volume", 1),
    }


def binding(segment_id: str, title: str, key_code: int, modifiers: list[str], volume: float = 1) -> dict:
    return {
        "id": title.lower().replace("+", "-").replace(" ", "-"),
        "title": title,
        "keyCode": key_code,
        "modifiers": modifiers,
        "sampleClipID": segment_id,
        "sampleVolume": volume,
    }


def build_theme(plan: dict) -> dict:
    segment_by_id = {segment["id"]: segment for segment in plan["segments"]}
    shortcut_map = plan["shortcutBindings"]

    return {
        "name": "shortcut-local-drops",
        "displayName": "本地快捷键掉宝器",
        "description": "使用 Samples/hajimi-local/segment-plan.json 按曲目结构裁剪的本地哈基米掉宝音效。",
        "sampleClips": [clip_entry(segment) for segment in plan["segments"]],
        "shortcutBindings": [
            binding(shortcut_map["cmd-c"], "Command+C Copy", 8, ["command"]),
            binding(shortcut_map["cmd-x"], "Command+X Cut", 7, ["command"]),
            binding(shortcut_map["cmd-v"], "Command+V Paste", 9, ["command"]),
            binding(shortcut_map["cmd-z"], "Command+Z Undo", 6, ["command"]),
            binding(shortcut_map["cmd-shift-z"], "Command+Shift+Z Redo", 6, ["command", "shift"], 0.92),
            binding(shortcut_map["cmd-s"], "Command+S Save", 1, ["command"], 0.95),
            binding(shortcut_map["cmd-a"], "Command+A Select All", 0, ["command"], 0.86),
            binding(shortcut_map["cmd-f"], "Command+F Find", 3, ["command"], 0.95),
            binding(shortcut_map["cmd-p"], "Command+P Palette/Print", 35, ["command"], 0.9),
            binding(shortcut_map["cmd-n"], "Command+N New", 45, ["command"], 0.9),
            binding(shortcut_map["cmd-w"], "Command+W Close", 13, ["command"], 0.9),
            binding(shortcut_map["cmd-tab"], "Command+Tab Switch", 48, ["command"], 0.9),
            binding(shortcut_map["function"], "F1", 122, [], 0.82),
            binding(shortcut_map["function"], "F2", 120, [], 0.82),
            binding(shortcut_map["function"], "F3", 99, [], 0.82),
            binding(shortcut_map["function"], "F4", 118, [], 0.82),
            binding(shortcut_map["function"], "F5", 96, [], 0.82),
            binding(shortcut_map["function"], "F6", 97, [], 0.82),
            binding(shortcut_map["function"], "F7", 98, [], 0.82),
            binding(shortcut_map["function"], "F8", 100, [], 0.82),
            binding(shortcut_map["function"], "F9", 101, [], 0.82),
            binding(shortcut_map["function"], "F10", 109, [], 0.82),
            binding(shortcut_map["function"], "F11", 103, [], 0.82),
            binding(shortcut_map["function"], "F12", 111, [], 0.82),
        ],
    }


def recut(segment: dict) -> None:
    source = ROOT / "Samples" / "hajimi-local" / "raw" / segment["source"]
    output = ROOT / segment["output"]
    output.parent.mkdir(parents=True, exist_ok=True)

    duration = float(segment["duration"])
    fade_in = float(segment.get("fadeIn", 0.04))
    fade_out = float(segment.get("fadeOut", 0.25))
    fade_out_start = max(0, duration - fade_out)
    filters = f"afade=t=in:st=0:d={fade_in},afade=t=out:st={fade_out_start}:d={fade_out}"

    run([
        "ffmpeg",
        "-hide_banner",
        "-y",
        "-ss",
        str(segment["start"]),
        "-t",
        str(duration),
        "-i",
        str(source),
        "-af",
        filters,
        str(output),
    ])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Recut Hajimi shortcut drop segments from segment-plan.json.")
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="Only recut the given segment id. Can be passed multiple times, e.g. --only drop-copy --only drop-paste.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List segment ids and exit.",
    )
    parser.add_argument(
        "--skip-audio",
        action="store_true",
        help="Only regenerate Themes/shortcut-local-drops.json without running ffmpeg.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    plan = json.loads(PLAN_PATH.read_text())

    if args.list:
        for segment in plan["segments"]:
            print(f'{segment["id"]}\t{segment["source"]}\tstart={segment["start"]}\tduration={segment["duration"]}')
        return

    selected_ids = set(args.only)
    unknown_ids = selected_ids - {segment["id"] for segment in plan["segments"]}
    if unknown_ids:
        raise SystemExit(f"Unknown segment id(s): {', '.join(sorted(unknown_ids))}")

    if not args.skip_audio:
        for segment in plan["segments"]:
            if selected_ids and segment["id"] not in selected_ids:
                continue

            recut(segment)

    THEME_PATH.write_text(json.dumps(build_theme(plan), ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
