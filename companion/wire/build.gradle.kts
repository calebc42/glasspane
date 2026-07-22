plugins {
    kotlin("jvm")
}

kotlin { jvmToolchain(21) }

dependencies {
    // org.json is the JSON surface shared with Android. compileOnly: on the
    // device the framework provides these classes; packaging the artifact
    // would shadow the boot classpath. JVM tests supply the reference jar.
    compileOnly("org.json:json:20240303")
    testImplementation("org.json:json:20240303")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    useJUnit()
    // The conformance suite reads the ebp submodule's goldens.
    systemProperty("ebp.dir", rootDir.resolve("../ebp").canonicalPath)
}
