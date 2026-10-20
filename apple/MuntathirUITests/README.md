# UI tests

Run the `Muntathir` scheme tests in Xcode on an iOS 26+ simulator, or from repository root:

```sh
xcodebuild test -project apple/Muntathir.xcodeproj -scheme Muntathir \
  -destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UUID' \
  -only-testing:MuntathirUITests
```

XCTest covers English/Arabic navigation, manual correction, and daily ayah sharing. Run on iPhone and iPad when changing layouts. UI tests remain manual and are not part of the pre-push hook. Simulator results do not establish proximity sensor accuracy.
