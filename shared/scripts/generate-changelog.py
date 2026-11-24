"""Generate the repository changelog from the English mobile release notes."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    catalog = ROOT / "shared/release-notes/changelog.json"
    entries = json.loads(catalog.read_text(encoding="utf-8"))
    entries.sort(key=lambda entry: tuple(map(int, entry["version"].split("."))), reverse=True)

    lines = ["# Changelog", "", "<!-- Generated from shared/release-notes/changelog.json by just changelog. -->"]
    for entry in entries:
        dates = entry.get("releaseDates", {})
        platform_names = {"ios": "iOS", "macos": "macOS", "android": "Android"}

        releases = [
            f"{platform_names[platform]} · {dates.get(platform) or 'Unreleased'}"
            for platform in entry["platforms"]
        ]
        lines.extend(["", f"## {entry['version']}", "", " · ".join(releases), ""])
        lines.extend(f"- {item}" for item in entry["notes"]["en-US"])

    (ROOT / "CHANGELOG.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
