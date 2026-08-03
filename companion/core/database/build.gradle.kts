plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kmp.library)
    alias(libs.plugins.ksp)
    alias(libs.plugins.room3)
}

kotlin {
    compilerOptions {
        freeCompilerArgs.add("-Xexpect-actual-classes")
    }
    jvmToolchain(21)

    jvm()

    android {
        namespace = "com.calebc42.jetpacs.core.database"
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
            implementation(projects.core.model)
            implementation(libs.androidx.room3.runtime)
            implementation(libs.androidx.sqlite.bundled)
            implementation(libs.kotlinx.coroutines.core)
        }
        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
        }
        getByName("androidDeviceTest").dependencies {
            implementation(libs.androidx.test.core)
            implementation(libs.androidx.test.ext.junit)
            implementation(libs.androidx.test.runner)
        }
    }
}

dependencies {
    add("kspJvm", libs.androidx.room3.compiler)
    add("kspAndroid", libs.androidx.room3.compiler)
}

room3 {
    schemaDirectory("$projectDir/schemas")
}

afterEvaluate {
    // Room's bundled Android driver requires device JNI packaging, not a host JVM.
    tasks.named("testAndroidHostTest") { enabled = false }
}
