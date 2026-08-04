plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kmp.library)
}

kotlin {
    jvmToolchain(21)

    jvm()

    android {
        namespace = "com.calebc42.jetpacs.core.ebpstore"
        compileSdk = 36
        minSdk = 36
        withHostTestBuilder {}
        withDeviceTestBuilder {
            sourceSetTreeName = "test"
        }.configure {
            instrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(projects.ebpKmp)
            implementation(projects.core.database)
            implementation(libs.androidx.room3.runtime)
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.serialization.json)
        }
        jvmTest.dependencies {
            implementation(libs.androidx.sqlite.bundled)
            implementation(libs.junit)
            implementation(libs.kotlinx.coroutines.test)
        }
        getByName("androidDeviceTest").dependencies {
            implementation(libs.androidx.test.core)
            implementation(libs.androidx.test.ext.junit)
            implementation(libs.androidx.test.runner)
            implementation(libs.junit)
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

tasks.named<Test>("jvmTest") {
    useJUnit()
}

tasks.register("test") {
    dependsOn("jvmTest")
}
