# UI tests

UI tests are run manually and aren't part of the pre-push hook. Run them on both iPhone and iPad when you change layouts:

```sh
xcodebuild test -project apple/Muntathir.xcodeproj -scheme Muntathir \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  -only-testing:MuntathirUITests
```

## Launch arguments

| Argument | Effect |
| --- | --- |
| `--ui-testing` | Base test mode. Skips onboarding. |
| `--ui-testing-onboarding` | Runs onboarding instead of skipping it. |
| `--ui-testing-mecca` | Seeds a deterministic location. |
| `--ui-testing-preserve-state` | Keeps test defaults across a relaunch. |
| `--ui-testing-hadith-fixture` | Uses an isolated local Hadith library, so no download is needed. |
| `--ui-testing-supplications-fixture` | Uses an isolated Supplications library. |
| `--ui-testing-legacy-highlights` | Seeds two overlapping whole-verse highlights. |

Check these on a real device: permission prompts, location denial, offline search, notification delivery, and CloudKit sync between two devices.
