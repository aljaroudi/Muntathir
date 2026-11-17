plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "com.aljaroudi.muntathir"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.aljaroudi.muntathir"
        minSdk = 26
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "com.aljaroudi.muntathir.HiltTestRunner"
        // Smart search (`/v1/search`), as in apple/Muntathir/Resources/SemanticSearchConfiguration.plist.
        val semanticSearchUrl =
            providers.gradleProperty("semanticSearchUrl").orElse("https://search.xn--pgbou4cf.com/v1/search").get()
        buildConfigField("String", "SEMANTIC_SEARCH_URL", "\"$semanticSearchUrl\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures.compose = true
    buildFeatures.buildConfig = true

    // Generates the per-app language list from res/values-* (see res/resources.properties).
    androidResources.generateLocaleConfig = true

    // Content databases ship as Play Asset Delivery packs; only the Quran text is in the base APK.
    assetPacks += listOf(":packs:hadith", ":packs:supplications")
    // Databases are copied out once; storing them uncompressed keeps that a plain stream copy.
    androidResources.noCompress += "db"

    testOptions {
        // Required by Compose Preview screenshot tests to resolve themes and fonts.
        unitTests.isIncludeAndroidResources = true
        screenshotTests.create("screenshotTest") {
            engineVersion = libs.versions.screenshot.get()
            targetVariants.add("debug")
            dependencies {
                implementation(libs.compose.ui.tooling)
                implementation(libs.screenshot.validation.api)
            }
        }
    }
}

// The Arabic Quran, the bundled English translation and the daily-verse schedule are shared with iOS.
val appleResources = rootProject.file("../apple/Muntathir/Resources")
val quranAssets =
    tasks.register<SharedContent>("quranAssets") {
        files.from(
            appleResources.resolve("Quran/quran.db"),
            appleResources.resolve("Quran/en.qarai.db"),
            appleResources.resolve("quran-daily-ids.json"),
            appleResources.resolve("quran-surahs.json"),
        )
        subdirectory = "quran"
        lowercase = false
        outputDir = layout.buildDirectory.dir("generated/shared/assets")
    }

// Alert sounds; resource names must be lowercase (`aliMulla.wav` → `R.raw.alimulla`).
val alertSounds =
    tasks.register<SharedContent>("alertSounds") {
        files.from(fileTree(appleResources) { include("*.wav") })
        subdirectory = "raw"
        lowercase = true
        outputDir = layout.buildDirectory.dir("generated/shared/res")
    }

// Third-party notices shown in Settings → Sources & licenses.
val licenseAssets =
    tasks.register<SharedContent>("licenseAssets") {
        files.from(appleResources.resolve("Adhan-LICENSE.txt"), appleResources.resolve("AdhanSounds-CREDITS.txt"))
        subdirectory = "licenses"
        lowercase = false
        outputDir = layout.buildDirectory.dir("generated/shared/licenses")
    }

androidComponents.onVariants { variant ->
    variant.sources.assets?.addGeneratedSourceDirectory(quranAssets, SharedContent::outputDir)
    variant.sources.assets?.addGeneratedSourceDirectory(licenseAssets, SharedContent::outputDir)
    variant.sources.res?.addGeneratedSourceDirectory(alertSounds, SharedContent::outputDir)
}

dependencies {
    implementation(project(":core"))
    // Platform SQLite lacks FTS5 on older releases; the bundled build has it everywhere.
    implementation(libs.androidx.sqlite.bundled)
    implementation(libs.play.asset.delivery.ktx)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.material3.adaptive.navigation.suite)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.material3.adaptive.navigation3)
    implementation(libs.androidx.hilt.lifecycle.viewmodel.compose)
    implementation(libs.androidx.datastore)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.androidx.work.runtime)
    implementation(libs.androidx.hilt.work)
    ksp(libs.androidx.hilt.compiler)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.play.services.location)
    // Offline time-zone boundaries for GPS fixes (city names come from Geocoder).
    implementation(libs.timezonemap)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.rules)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
    androidTestImplementation(libs.hilt.android.testing)
    kspAndroidTest(libs.hilt.compiler)
}

/** Copies files owned by the Apple app into a generated source directory, optionally lowercasing names. */
abstract class SharedContent : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NAME_ONLY)
    abstract val files: ConfigurableFileCollection

    @get:Input
    abstract val subdirectory: Property<String>

    @get:Input
    abstract val lowercase: Property<Boolean>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun copy() {
        val root = outputDir.get().asFile
        root.deleteRecursively()
        val target = root.resolve(subdirectory.get()).apply { mkdirs() }
        files.forEach { it.copyTo(target.resolve(if (lowercase.get()) it.name.lowercase() else it.name)) }
    }
}
