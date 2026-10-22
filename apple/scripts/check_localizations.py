"""Check Apple interface translations, placeholders, and localized content."""

import json
import re
from pathlib import Path

APPLE = Path(__file__).resolve().parents[1]
LOCALES = {"ar", "en", "fr", "de", "id", "it", "ja", "ms", "fa", "ru", "es", "tr", "ur", "zh-Hans", "zh-Hant"}


def strings(value):
    if "stringUnit" in value:
        yield value["stringUnit"]["value"]
    for variation in value.get("variations", {}).values():
        for child in variation.values():
            yield from strings(child)


def arguments(text):
    return sorted(re.sub(r"\d+\$", "", item) for item in re.findall(r"%(?:\d+\$)?(?:lld|@)|%%", text))


def main():
    catalog = json.loads((APPLE / "Muntathir/Localizable.xcstrings").read_text())["strings"]
    for key, entry in catalog.items():
        localized = entry.get("localizations", {})
        assert LOCALES <= localized.keys(), f"Missing locales: {key}"
        for locale in LOCALES:
            values = list(strings(localized[locale]))
            assert values, f"Missing text: {locale}: {key}"
            for value in values:
                assert value.strip(), f"Empty text: {locale}: {key}"
                assert arguments(key) == arguments(value), f"Placeholder mismatch: {locale}: {key}"
                assert "{apple}" not in value and "{events}" not in value, f"Unresolved link: {locale}: {key}"
    events = json.loads((APPLE / "Muntathir/Resources/events.json").read_text())
    for event in events:
        assert LOCALES <= event["titles"].keys(), f"Missing event locale: {event['id']}"
        assert all(event["titles"][locale].strip() for locale in LOCALES)
    for locale in LOCALES:
        permission = (APPLE / "Muntathir" / f"{locale}.lproj/InfoPlist.strings").read_text()
        assert '"NSLocationWhenInUseUsageDescription"' in permission, f"Missing location purpose: {locale}"
    print(f"Validated {len(catalog)} interface strings and {len(events)} observances in {len(LOCALES)} locales.")


if __name__ == "__main__":
    main()
