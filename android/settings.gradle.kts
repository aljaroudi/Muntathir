pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Muntathir"

include(":core", ":app")

// The Wear OS app (prayer list, complications, tile); same application id as :app.
include(":wear")

// Test-only: generates the app's Baseline Profile on a device (P7.2). Never shipped.
include(":baselineprofile")

// Play Asset Delivery packs; their databases are copied in by `just android-packs` (apple/AssetPacks/assets.py).
include(":packs:hadith", ":packs:supplications", ":packs:quran_translations", ":packs:rulings", ":packs:lexicon")
