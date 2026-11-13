import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val separateAndroidPlayback = providers.gradleProperty("dart-defines").orNull
    ?.split(',')
    ?.map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    ?.lastOrNull { it.startsWith("KANADE_SEPARATE_ANDROID_PLAYBACK=") }
    ?.substringAfter('=')
    ?.toBooleanStrict()
    ?: true
val nacModel = providers.environmentVariable("KANADE_NAC_MODEL").orNull?.let { file(it) }
    ?: file("nac-local/7187332.mnn").takeIf { it.isFile }
val dtsRuntime = providers.environmentVariable("KANADE_DTS_ANDROID_RUNTIME").orNull?.let { file(it) }
    ?: file("dts-local").takeIf { it.isDirectory }
val ra360Runtime = providers.environmentVariable("KANADE_RA360_ANDROID_RUNTIME").orNull?.let { file(it) }
    ?: file("ra360-local").takeIf { it.isDirectory }

android {
    namespace = "com.lxi.kanade"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lxi.kanade"
        manifestPlaceholders["playbackProcess"] = if (separateAndroidPlayback) ":playback" else applicationId!!
        manifestPlaceholders["separateAndroidPlayback"] = separateAndroidPlayback.toString()
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        if (nacModel != null || dtsRuntime != null || ra360Runtime != null) {
            if (nacModel != null) {
                require(nacModel.isFile) { "KANADE_NAC_MODEL must point to the NAC model file" }
            }
            externalNativeBuild {
                cmake {
                    abiFilters += "arm64-v8a"
                    arguments += listOf(
                        "-DANDROID_STL=c++_shared",
                        "-DKANADE_NAC_MODEL=${nacModel?.invariantSeparatorsPath.orEmpty()}",
                        "-DKANADE_DTS_ANDROID_RUNTIME=${dtsRuntime?.invariantSeparatorsPath.orEmpty()}",
                        "-DKANADE_RA360_ANDROID_RUNTIME=${ra360Runtime?.invariantSeparatorsPath.orEmpty()}",
                    )
                }
            }
        }
    }

    if (nacModel != null) {
        sourceSets.getByName("main").assets.srcDir("../../native/nac/licenses")
    }
    if (ra360Runtime != null) {
        // QQ Music's 360RA decoder libraries, loaded at run time by libkanade_ra360.so.
        sourceSets.getByName("main").jniLibs.srcDir(ra360Runtime.resolve("jni"))
    }
    if (nacModel != null || dtsRuntime != null || ra360Runtime != null) {
        externalNativeBuild {
            cmake {
                path = file("../../native/android/CMakeLists.txt")
                version = "3.22.1"
            }
        }
    }

    // Only ship arm64. abiFilters doesn't work here because the Flutter plugin
    // appends every target ABI, and media_kit ships prebuilt libmpv for all of them.
    packaging {
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
            // Prebuilt by QQ Music with symbol tables newer tools reject; ship them as they are.
            keepDebugSymbols += listOf("**/libqm_native_decoder_360ra.so", "**/libaudio_common.so", "**/libextra_mp4_parser.so")
        }
    }

    // android/key.properties 存在时（CI 从 secrets 生成）使用正式签名，否则用 debug 签名
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // FileProvider：把下载好的更新安装包交给系统安装器
    implementation("androidx.core:core:1.13.1")
}
