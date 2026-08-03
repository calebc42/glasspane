plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kmp.library)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(21)

    jvm()

    android {
        namespace = "com.calebc42.jetpacs.core.navigation"
        compileSdk = 36
        minSdk = 36
        withHostTestBuilder {}
    }

    sourceSets {
        commonMain.dependencies {
            implementation(libs.androidx.navigation3.runtime)
            implementation(libs.kotlinx.serialization.core)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
        }
    }
}
