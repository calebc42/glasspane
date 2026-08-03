// POC 3 keeps the proven wire/app pair intact and grows architecture-template
// style core modules around the future standalone kotlin-ebp library.
enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

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
include(":core:model")
include(":core:database")
include(":core:data")
include(":core:navigation")
include(":core:testing")
