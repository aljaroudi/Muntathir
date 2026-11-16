import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions.jvmTarget = JvmTarget.JVM_17
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    // CommonMark, like Foundation's cmark-based Markdown, so hadith text renders as on iOS.
    implementation(libs.commonmark)
    implementation(libs.commonmark.strikethrough)
    testImplementation(libs.kotlin.test)
    testImplementation(libs.sqlite.jdbc)
}

// Content shared with the Apple app ships as classpath resources.
tasks.processResources {
    from(rootProject.file("../shared")) { include("events.json", "ummalqura.json") }
}

tasks.test {
    // Fixtures are shared with the Apple tests; see shared/fixtures/README.md.
    val fixtures = rootProject.file("../shared/fixtures")
    inputs.dir(fixtures)
    systemProperty("fixtures", fixtures.absolutePath)
    // Read-only inputs owned by other parts of the repository (bundled Quran DB, production feed).
    val repository = rootProject.file("..")
    inputs.file(repository.resolve("apple/Muntathir/Resources/Quran/quran.db"))
    inputs.file(repository.resolve("apple/Muntathir/Resources/quran-surahs.json"))
    inputs.file(repository.resolve("web/public/calendar/corrections-v1.json"))
    systemProperty("repository", repository.absolutePath)
}
