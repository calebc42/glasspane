plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin { jvmToolchain(21) }

dependencies {
    // org.json is the JSON surface shared with Android. compileOnly: on the
    // device the framework provides these classes; packaging the artifact
    // would shadow the boot classpath. JVM tests supply the reference jar.
    compileOnly(libs.json)
    testImplementation(libs.json)
    testImplementation(libs.junit)
}

tasks.test {
    useJUnit()
    // The conformance suite reads the ebp submodule's goldens.
    systemProperty("ebp.dir", rootDir.resolve("../ebp").canonicalPath)
}
