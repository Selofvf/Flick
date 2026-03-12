package com.selov.flick

import android.content.ComponentName
import android.content.pm.PackageManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.selov.flick/icon"
    private val TAG     = "FlickIcon"

    private val aliases = mapOf(
        "default" to ".MainActivityDefault",
        "green"   to ".MainActivityGreen",
        "pink"    to ".MainActivityPink",
        "orange"  to ".MainActivityOrange",
        "blue"    to ".MainActivityBlue",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "MethodChannel call: ${call.method}")
                if (call.method == "setIcon") {
                    val key = call.argument<String>("icon") ?: "default"
                    Log.d(TAG, "Switching icon to: $key")
                    try {
                        switchIcon(key)
                        Log.d(TAG, "Icon switched successfully")
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error switching icon: ${e.message}")
                        result.error("ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun switchIcon(selectedKey: String) {
        val pm          = packageManager
        val packageName = this.packageName
        Log.d(TAG, "Package name: $packageName")

        for ((key, suffix) in aliases) {
            val componentName = "$packageName$suffix"
            val component     = ComponentName(packageName, componentName)
            val state = if (key == selectedKey)
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED

            Log.d(TAG, "Setting $componentName -> $state")
            pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        }
    }
}