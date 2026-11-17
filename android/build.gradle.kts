plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.asset.pack) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt) apply false
    alias(libs.plugins.androidx.room) apply false
    alias(libs.plugins.spotless)
}

spotless {
    val ktlint = libs.versions.ktlint.get()
    kotlin {
        target("**/src/**/*.kt")
        ktlint(ktlint)
    }
    kotlinGradle {
        target("*.kts", "*/*.kts", "*/*/*.kts")
        ktlint(ktlint)
    }
}

// bundletool from Google Maven, so no local install is needed: ./gradlew bundletool --args="version"
val bundletool: Configuration by configurations.creating

dependencies {
    bundletool(libs.bundletool)
    // install-apks uses ddmlib, which needs the Kotlin stdlib that bundletool's POM omits.
    bundletool(kotlin("stdlib", libs.versions.kotlin.get()))
}

tasks.register<JavaExec>("bundletool") {
    description = "Runs bundletool, e.g. --args=\"build-apks --local-testing ...\"."
    classpath = bundletool
    mainClass = "com.android.tools.build.bundletool.BundleToolMain"
    workingDir = rootDir
}
