plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kmp.library)
}

kotlin {
    jvmToolchain(21)

    jvm()

    android {
        namespace = "com.calebc42.jetpacs.core.data"
        compileSdk = 36
        minSdk = 34
        withHostTestBuilder {}
    }

    sourceSets {
        commonMain.dependencies {
            api(projects.core.model)
            implementation(projects.core.database)
            implementation(libs.androidx.room3.runtime)
            implementation(libs.kotlinx.coroutines.core)
        }
        commonTest.dependencies {
            implementation(libs.androidx.sqlite.bundled)
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

afterEvaluate {
    // Room's bundled Android driver requires device JNI packaging, not a host JVM.
    tasks.named("testAndroidHostTest") { enabled = false }
}
