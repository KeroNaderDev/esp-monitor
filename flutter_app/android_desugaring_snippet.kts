// Required by flutter_local_notifications (core library desugaring).
// Add to android/app/build.gradle.kts:

// 1. Inside android { compileOptions { ... } }:
isCoreLibraryDesugaringEnabled = true

// 2. At the end of the file:
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
