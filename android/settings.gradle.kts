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

// Play Asset Delivery packs; their databases are copied in by `just android-packs` (apple/AssetPacks/assets.py).
include(":packs:hadith", ":packs:supplications")
