import com.android.build.api.artifact.SingleArtifact
import com.android.build.api.variant.BuiltArtifactsLoader
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
// Debug builds can update from a server on your LAN (scripts/serve-dev-update.sh). The host comes from the
// gitignored .env at the repository root (or the environment), so no address is ever committed.
val dotEnv = providers.fileContents(layout.projectDirectory.file("../../.env")).asText.orNull.orEmpty()
    .lineSequence().map(String::trim).filter { it.isNotEmpty() && !it.startsWith("#") && "=" in it }
    .associate { line -> line.substringBefore("=").removePrefix("export ").trim() to line.substringAfter("=").trim().trim('"', '\'') }
fun devSetting(name: String) = providers.environmentVariable(name).orNull ?: dotEnv[name]
val devUpdateHost = devSetting("AQUARESTORE_DEV_UPDATE_HOST")?.takeIf(String::isNotBlank)?.also {
    require(Regex("^[A-Za-z0-9.-]+$").matches(it)) { "AQUARESTORE_DEV_UPDATE_HOST must be an IPv4 address or host name" }
}
val devUpdatePort = (devSetting("AQUARESTORE_DEV_UPDATE_PORT") ?: "8765").also {
    require(it.toIntOrNull() in 1..65535) { "AQUARESTORE_DEV_UPDATE_PORT must be a port number" }
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
        buildConfigField("String", "DEV_UPDATE_URL", "\"\"")
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
            buildConfigField("String", "UPDATE_CHANNEL", if (devUpdateHost == null) "\"none\"" else "\"lan\"")
            if (devUpdateHost != null) buildConfigField("String", "DEV_UPDATE_URL", "\"http://$devUpdateHost:$devUpdatePort/\"")
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
        // Network, install permission and FileProvider exist in debug only when a LAN update server is set.
        if (devUpdateHost != null) getByName("debug") {
            manifest.srcFile("src/lanUpdate/AndroidManifest.xml")
            res.srcDir("src/lanUpdate/res")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    lint { disable += "UnsafeOptInUsageError" }
}
if (devUpdateHost != null) androidComponents.onVariants(androidComponents.selector().withBuildType("debug")) { variant ->
    // Every LAN build must count as newer than the installed one: minutes since 2026-01-01 UTC.
    val stamp = (System.currentTimeMillis() / 60_000 - 29_453_760).toInt()
    variant.outputs.forEach { it.versionCode.set(stamp) }
    val network = tasks.register<LanNetworkConfig>("${variant.name}LanNetworkConfig") { host.set(devUpdateHost) }
    variant.sources.res?.addGeneratedSourceDirectory(network, LanNetworkConfig::outputDir)
    val publish = tasks.register<PublishLanUpdate>("${variant.name}PublishLanUpdate") {
        apkFolder.set(variant.artifacts.get(SingleArtifact.APK))
        loader.set(variant.artifacts.getBuiltArtifactsLoader())
        outputDir.set(rootProject.layout.projectDirectory.dir("dist/dev-update"))
    }
    tasks.matching { it.name == "assemble${variant.name.replaceFirstChar(Char::uppercase)}" }.configureEach { finalizedBy(publish) }
}

/** Lets the debug app use plain HTTP to the LAN update host and nowhere else. */
abstract class LanNetworkConfig : DefaultTask() {
    @get:Input abstract val host: Property<String>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @TaskAction fun write() {
        outputDir.get().file("xml/lan_update_network.xml").asFile.apply { parentFile.mkdirs() }.writeText("""
            <network-security-config>
                <domain-config cleartextTrafficPermitted="true"><domain includeSubdomains="false">${host.get()}</domain></domain-config>
            </network-security-config>
        """.trimIndent())
    }
}

/** Copies the debug APK to android/dist/dev-update with the latest.json and SHA256SUMS that the app reads. */
abstract class PublishLanUpdate : DefaultTask() {
    @get:InputFiles abstract val apkFolder: DirectoryProperty
    @get:Internal abstract val loader: Property<BuiltArtifactsLoader>
    @get:OutputDirectory abstract val outputDir: DirectoryProperty
    @TaskAction fun publish() {
        val built = loader.get().load(apkFolder.get()) ?: throw GradleException("No debug APK was built")
        val output = built.elements.single()
        val code = output.versionCode ?: throw GradleException("The debug APK has no version code")
        val directory = outputDir.get().asFile.apply { mkdirs() }
        directory.listFiles()?.filter { it.name.startsWith("AquaRestore-debug-") }?.forEach { it.delete() }
        val name = "AquaRestore-debug-$code.apk"
        val apk = File(output.outputFile).copyTo(File(directory, name), overwrite = true)
        val sha = MessageDigest.getInstance("SHA-256").digest(apk.readBytes()).joinToString("") { "%02x".format(it) }
        File(directory, "AquaRestore-debug-$code.SHA256SUMS").writeText("$sha  $name\n")
        val json = """{"versionCode":$code,"versionName":"${output.versionName.orEmpty()}","apk":"$name","size":${apk.length()}}"""
        File(directory, "latest.json.part").apply { writeText(json + "\n") }.renameTo(File(directory, "latest.json"))
        logger.lifecycle("LAN update: android/dist/dev-update/$name (versionCode $code)")
    }
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
