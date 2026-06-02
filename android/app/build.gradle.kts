plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader ->
        localProperties.load(reader)
    }
}

def flutterVersionCode = localProperties.getProperty('flutter.versionCode')
if (flutterVersionCode == null) flutterVersionCode = '1'
def flutterVersionName = localProperties.getProperty('flutter.versionName')
if (flutterVersionName == null) flutterVersionName = '1.0.0'

android {
    namespace = "io.xmrt.node"
    compileSdk = 34
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_1_8
    }

    defaultConfig {
        applicationId = "io.xmrt.node"
        minSdk = 24
        targetSdk = 34
        versionCode = flutterVersionCode.toInteger()
        versionName = flutterVersionName
        ndk { abiFilters "arm64-v8a" }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.debug
            minifyEnabled = true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }

    externalNativeBuild {
        cmake {
            path = "../xmrig/CMakeLists.txt"
            version = "3.22.1"
        }
    }
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlinx-coroutines-android:1.7.3"
    implementation "org.jetbrains.kotlin:kotlin-stdlib"
    implementation "androidx.core:core-ktx:1.12.0"
    implementation "com.squareup.okhttp3:okhttp:4.12.0"
    implementation "com.squareup.okhttp3:okhttp-sse:4.12.0"
}
