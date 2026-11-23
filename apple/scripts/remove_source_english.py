"""Remove English localizations that merely repeat the source string (the key) from the string catalog."""

import json
from pathlib import Path

APPLE = Path(__file__).resolve().parents[1]
CATALOG = APPLE / "Muntathir/Localizable.xcstrings"


def main():
    text = CATALOG.read_text()
    data = json.loads(text)
    removed = 0
    differing = []
    for key, entry in data["strings"].items():
        # Entries that are not translated keep their English text.
        if not entry.get("shouldTranslate", True):
            continue
        localized = entry.get("localizations", {})
        english = localized.get("en")
        if english is None:
            continue
        unit = english.get("stringUnit")
        if unit is not None and "variations" not in english and unit["value"] == key:
            del localized["en"]
            removed += 1
        else:
            differing.append(key)
    # Match Xcode's formatting so the diff only contains the removals.
    CATALOG.write_text(json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : ")))
    print(f"Removed {removed} English localizations equal to their source.")
    if differing:
        print("Kept English localizations that differ from the source:")
        for key in differing:
            print(f"  {key!r}")


if __name__ == "__main__":
    main()
