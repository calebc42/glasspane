// AGP 9 carries built-in Kotlin; only the compose compiler plugin is added.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.calebc42.ebp.companion"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.calebc42.ebp.companion"
        minSdk = 34
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0-w4"
    }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":wire")) // org.json comes from the framework
    implementation(platform("androidx.compose:compose-bom:2026.02.01"))
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
}
