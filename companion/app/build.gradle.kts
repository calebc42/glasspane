// AGP 9 carries built-in Kotlin; only the compose compiler plugin is added.
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
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
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation(projects.wire) // org.json comes from the framework
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material.icons)
    // JVM unit tests (the NodeSupport pin test): the framework isn't present,
    // so tests supply the reference org.json jar exactly as :wire does.
    testImplementation(libs.junit)
    testImplementation(libs.json)
}
