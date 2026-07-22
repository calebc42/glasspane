// The companion's Gradle root: the pure-JVM :wire protocol module plus the
// :app Android module that hosts it on the device.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "ebp-companion"
include(":wire")
include(":app")
