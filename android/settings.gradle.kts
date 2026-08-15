// 可选本地代理：android/gradle-proxy.properties（见 gradle-proxy.properties.example）
run {
    val proxyFile = file("gradle-proxy.properties")
    if (proxyFile.exists()) {
        val props = java.util.Properties()
        proxyFile.inputStream().use { props.load(it) }
        val enabled = props.getProperty("enabled", "true").equals("true", ignoreCase = true)
        if (enabled) {
            props.forEach { key, value ->
                val k = key.toString()
                if (k.startsWith("systemProp.")) {
                    System.setProperty(k.removePrefix("systemProp."), value.toString())
                }
            }
        }
    }
}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
