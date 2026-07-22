// One toolchain for every module (the PoC's proven stack).
plugins {
    id("com.android.application") version "9.1.1" apply false
    kotlin("jvm") version "2.1.10" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.10" apply false
}
