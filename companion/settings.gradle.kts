// The companion's Gradle root. W2 ships only the pure-JVM wire module;
// Android modules join at W4 (they will need an Android SDK).
rootProject.name = "ebp-companion"
include(":wire")
