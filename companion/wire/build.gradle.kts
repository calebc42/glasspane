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
            // org.json is the JSON surface shared with Android. compileOnly: on
            // the device the framework provides these classes; packaging the
            // artifact would shadow the boot classpath. JVM tests supply the
            // reference jar. (Deleted by RF-2b.)
            compileOnly(libs.json)
        }
        jvmTest.dependencies {
            implementation(libs.json)
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
