import java.util.Properties

// The Wear OS app: prayer list, complications and a tile, fed by the phone's settings snapshot (`WatchSync`).
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

val localProperties =
    rootProject
        .file("local.properties")
        .takeIf { it.isFile }
        ?.reader()
        ?.use { reader -> Properties().apply { load(reader) } }

// Same upload key as :app (see app/build.gradle.kts); the Data Layer only connects apps signed alike.
val upload: Map<String, String?> =
    listOf("UPLOAD_STORE_FILE", "UPLOAD_STORE_PASSWORD", "UPLOAD_KEY_ALIAS", "UPLOAD_KEY_PASSWORD")
        .associateWith { providers.gradleProperty(it).orNull ?: localProperties?.getProperty(it) }
if (providers.gradleProperty("requireUploadSigning").orNull == "true") {
    require(
        upload.values.all {
            !it.isNullOrBlank()
        },
    ) { "Configure the Play upload key in android/local.properties or Gradle properties." }
}

android {
    namespace = "com.aljaroudi.muntathir.watch"
    compileSdk = 37

    defaultConfig {
        // The phone's id: Play pairs them as one listing and the Data Layer requires a match.
        applicationId = "com.aljaroudi.muntathir"
        minSdk = 30
        targetSdk = 37
        // Phone and watch builds share a listing, so their codes must never collide.
        versionCode = 100_000 + (providers.gradleProperty("playVersionCode").orNull?.toInt() ?: 5)
        versionName =
            providers
                .fileContents(rootProject.layout.projectDirectory.file("../Version.xcconfig"))
                .asText
                .map { it.trim().removePrefix("MARKETING_VERSION = ") }
                .get()
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    if (upload.values.all { it != null }) {
        signingConfigs.create("upload") {
            storeFile = rootProject.file(upload.getValue("UPLOAD_STORE_FILE")!!)
            storePassword = upload["UPLOAD_STORE_PASSWORD"]
            keyAlias = upload["UPLOAD_KEY_ALIAS"]
            keyPassword = upload["UPLOAD_KEY_PASSWORD"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures.compose = true
    androidResources.generateLocaleConfig = true
}

dependencies {
    implementation(project(":core"))
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.play.services)
    implementation(libs.play.services.wearable)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.wear.compose.material3)
    implementation(libs.wear.compose.foundation)
    implementation(libs.wear.tooling.preview)
    implementation(libs.wear.remote.interactions)
    implementation(libs.wear.tiles)
    implementation(libs.wear.protolayout)
    implementation(libs.wear.protolayout.material3)
    implementation(libs.androidx.concurrent.futures)
    implementation(libs.wear.complications.data.source)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.wear.compose.ui.tooling)
    debugImplementation(libs.wear.tiles.tooling.preview)

    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
    debugImplementation(libs.compose.ui.test.manifest)
}
