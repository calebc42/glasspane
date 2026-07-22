plugins {
    kotlin("jvm") version "2.0.21"
}

kotlin { jvmToolchain(21) }

repositories {
    mavenCentral()
}

dependencies {
    // org.json is the JSON surface shared with Android (where the platform
    // provides it); on the JVM we depend on the reference artifact.
    implementation("org.json:json:20240303")
    testImplementation("junit:junit:4.13.2")
}

tasks.test {
    useJUnit()
    // The conformance suite reads the ebp submodule's goldens.
    systemProperty("ebp.dir", rootDir.resolve("../ebp").canonicalPath)
}
