plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.kmp.library)
}

kotlin {
    jvmToolchain(21)

    jvm()

    android {
        namespace = "com.calebc42.ebp.kmp"
        compileSdk = 36
        minSdk = 36
        withHostTestBuilder {}
    }

    sourceSets {
        commonMain.dependencies {
            // JsonElement is part of the portable EBP API.
            api(libs.kotlinx.serialization.json)
        }
        jvmTest.dependencies {
            implementation(libs.junit)
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}

tasks.named<Test>("jvmTest") {
    useJUnit()
}

// Preserve the conventional library gate alongside KMP's target-specific task.
tasks.register("test") {
    dependsOn("jvmTest")
}
