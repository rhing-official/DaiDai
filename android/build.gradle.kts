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
// 古いcompileSdk（31）のまま更新されていないプラグイン（keyboard_height_plugin）が、
// 依存するandroidxの要求（34以上）でAARメタデータの検査に失敗するため、ライブラリ側の
// compileSdkを引き上げる（2026-11-12）。targetSdk・minSdkは変えない。
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            if (android is com.android.build.gradle.LibraryExtension &&
                (android.compileSdk ?: 0) < 34
            ) {
                android.compileSdk = 36
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
