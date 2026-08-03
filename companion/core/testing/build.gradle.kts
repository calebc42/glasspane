plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kmp.library)
}

kotlin {
    jvmToolchain(21)

    jvm()

    android {
        namespace = "com.calebc42.jetpacs.core.testing"
        compileSdk = 36
        minSdk = 36
        withHostTestBuilder {}
    }

    sourceSets {
        commonMain.dependencies {
            api(projects.core.data)
            api(projects.core.model)
            implementation(libs.kotlinx.coroutines.core)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.kotlinx.coroutines.core)
        }
    }
}
