allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// flutter_pcm_sound 3.3.3 still compiles against android-33, but the AndroidX
// libraries it pulls in need 34+ (checkDebugAarMetadata failed in CI run
// 44418906637). Raise compileSdk of old plugin modules to the app's value.
// compileSdk only changes the API stubs used to compile, not runtime
// behaviour (minSdk/targetSdk are untouched). Registered before
// evaluationDependsOn so it runs before AGP finalises each plugin's DSL.
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            val android = extensions.findByName("android") ?: return@afterEvaluate
            val current = android.withGroovyBuilder { getProperty("compileSdk") } as Int?
            if (current == null || current < 37) {
                android.withGroovyBuilder { setProperty("compileSdk", 37) }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
