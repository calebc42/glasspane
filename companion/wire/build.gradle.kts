// RF-2a: the wire core is a Kotlin Multiplatform module. Only the JVM target is
// declared today and every source file still lives in jvmMain — the flip is a
// build-system change, not a source change. RF-2c hoists the pure core into
// commonMain, at which point `java.*` being unresolvable there *is* the purity
// proof that today rests on convention.
plugins {
    alias(libs.plugins.kotlin.multiplatform)
}

kotlin {
    jvmToolchain(21)

    jvm()

    sourceSets {
        jvmMain.dependencies {
            // RF-2b: `api`, not `implementation` — JsonElement appears in
            // :wire's public signatures consumed by :app. Tree API only; no
            // serialization compiler plugin, zero @Serializable.
            api(libs.kotlinx.serialization.json)
            // org.json left this module at C4 (jvmMain) and C5 (jvmTest): with
            // the jar off both classpaths, a stray re-imported org.json symbol
            // is a compile error, not a silent regression.
        }
        jvmTest.dependencies {
            implementation(libs.junit)
        }
    }
}

// KMP has no `test` task and no top-level `dependencies {}`. The `ebp.dir`
// property must ride `jvmTest` or five conformance suites lose their fixtures.
tasks.named<Test>("jvmTest") {
    useJUnit()
    // The conformance suite reads the ebp submodule's goldens.
    systemProperty("ebp.dir", rootDir.resolve("../ebp").canonicalPath)
}

// Keeps the documented gate command (`./gradlew :wire:test`) working.
tasks.register("test") { dependsOn("jvmTest") }
