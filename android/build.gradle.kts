import com.android.build.gradle.LibraryExtension

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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    afterEvaluate {
        if (!plugins.hasPlugin("com.android.library")) return@afterEvaluate

        val androidExt = extensions.findByType(LibraryExtension::class.java) ?: return@afterEvaluate
        if (!androidExt.namespace.isNullOrBlank()) return@afterEvaluate

        val manifestFile = file("src/main/AndroidManifest.xml")
        if (!manifestFile.exists()) return@afterEvaluate

        val packageName = Regex("""package\s*=\s*"([^"]+)"""")
            .find(manifestFile.readText())
            ?.groupValues
            ?.getOrNull(1)

        if (!packageName.isNullOrBlank()) {
            androidExt.namespace = packageName
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
