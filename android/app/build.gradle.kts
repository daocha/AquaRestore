plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.aquarestore.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.aquarestore.app"
        minSdk = 29
        targetSdk = 36
        versionCode = 5
        versionName = "2026.10.25"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["appLabel"] = "AquaRestore"
    }
    val releaseKeystore = providers.environmentVariable("AQUARESTORE_KEYSTORE_FILE").orNull
    signingConfigs {
        if (releaseKeystore != null) create("localRelease") {
            storeFile = file(releaseKeystore)
            storePassword = providers.environmentVariable("AQUARESTORE_KEYSTORE_PASSWORD").orNull
            keyAlias = providers.environmentVariable("AQUARESTORE_KEY_ALIAS").orNull
            keyPassword = providers.environmentVariable("AQUARESTORE_KEY_PASSWORD").orNull
        }
    }
    buildTypes {
        // Own package name and label so the debug build installs next to (not over) a release build signed with a different key.
        debug {
            applicationIdSuffix = ".debug"; versionNameSuffix = "-debug"
            manifestPlaceholders["appLabel"] = "AquaRestore Dev"
            buildConfigField("String", "UPDATE_CHANNEL", "\"none\"")
        }
        release {
            isDebuggable = false
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            buildConfigField("String", "UPDATE_CHANNEL", "\"github\"")
            if (releaseKeystore != null) signingConfig = signingConfigs.getByName("localRelease")
        }
        // Upload this variant to Play. It has no APK-install permission or GitHub update route.
        create("playRelease") {
            initWith(getByName("release"))
            matchingFallbacks += listOf("release")
            buildConfigField("String", "UPDATE_CHANNEL", "\"play\"")
        }
    }
    // The tuned grading comes from the private core submodule; scripts/use-core-stub.sh fills core/ with a basic one.
    val core = rootProject.file("../core/android")
    check(core.resolve("main").isDirectory) {
        "core/ is empty: run `git submodule update --init`, or scripts/use-core-stub.sh without access to the private core."
    }
    sourceSets {
        getByName("main").java.srcDir(core.resolve("main"))
        getByName("test").java.srcDir(core.resolve("test"))
        getByName("androidTest").java.srcDir(core.resolve("androidTest"))
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    lint { disable += "UnsafeOptInUsageError" }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.12.01"))
    implementation("androidx.activity:activity-compose:1.12.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("androidx.media3:media3-exoplayer:1.9.3")
    implementation("androidx.media3:media3-ui:1.9.3")
    implementation("androidx.media3:media3-effect:1.9.3")
    implementation("androidx.media3:media3-transformer:1.9.3")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.12.01"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}
