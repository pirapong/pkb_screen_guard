package com.pkbstudio.pkbscreenguard

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader

/** Android implementation for pkb_screen_guard */
class PkbScreenGuardPlugin : FlutterPlugin,
  MethodChannel.MethodCallHandler,
  ActivityAware,
  EventChannel.StreamHandler {

  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel: EventChannel

  private var applicationContext: Context? = null
  private var activity: Activity? = null
  private var eventSink: EventSink? = null

  // overlay view
  private var overlayView: View? = null

  // monitoring
  @Volatile
  private var monitoring = false
  private var monitorThread: Thread? = null

  override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    methodChannel = MethodChannel(binding.binaryMessenger, "pkb_screen_guard/methods")
    methodChannel.setMethodCallHandler(this)

    eventChannel = EventChannel(binding.binaryMessenger, "pkb_screen_guard/events")
    eventChannel.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    applicationContext = null
  }

  // ActivityAware
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  // MethodChannel
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "enableSecure" -> {
        runOnUi {
          it.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        result.success(null)
      }
      "disableSecure" -> {
        runOnUi {
          it.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        result.success(null)
      }
      "startMonitoring" -> {
        startMonitoring()
        result.success(null)
      }
      "stopMonitoring" -> {
        stopMonitoring()
        result.success(null)
      }
      "checkRooted" -> {
        result.success(isDeviceRooted())
      }
      "showOverlay" -> {
        showOverlay()
        result.success(null)
      }
      "hideOverlay" -> {
        hideOverlay()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun runOnUi(block: (Activity) -> Unit) {
    val act = activity ?: return
    act.runOnUiThread { block(act) }
  }

  // ---------- Monitoring loop (root / hook / remote / external display) ----------

  private fun startMonitoring() {
    if (monitoring) return
    monitoring = true

    monitorThread = Thread {
      var lastRoot = false
      var lastExternalDisplay = false
      var lastRemotePkg: String? = null
      var lastHook = false

      while (monitoring) {
        try {
          // root
          val rooted = isDeviceRooted()
          if (rooted != lastRoot) {
            lastRoot = rooted
            sendEvent(
              mapOf(
                "event" to if (rooted) "rootDetected" else "rootCleared",
                "score" to if (rooted) 10 else 0
              )
            )
          }

          // hook / Frida / Xposed heuristic
          val hook = isHookFrameworkPresent()
          if (hook != lastHook) {
            lastHook = hook
            if (hook) {
              sendEvent(mapOf("event" to "hookDetected"))
            }
          }

          // external display
          val external = isExternalDisplayConnected()
          if (external != lastExternalDisplay) {
            lastExternalDisplay = external
            sendEvent(
              mapOf(
                "event" to if (external) "externalDisplayAttached"
                else "externalDisplayDetached"
              )
            )
            if (external) {
              // บังจอเมื่อมี external display / cast
              showOverlay()
            } else {
              hideOverlay()
            }
          }

          // remote apps installed
          val remotePkg = detectRemoteControlApp()
          if (remotePkg != lastRemotePkg) {
            lastRemotePkg = remotePkg
            if (remotePkg != null) {
              sendEvent(
                mapOf(
                  "event" to "remoteAppDetected",
                  "package" to remotePkg
                )
              )
              // ถือว่ามีความเสี่ยงสูง → บังจอ
              showOverlay()
            }
          }

          Thread.sleep(1500)
        } catch (_: Throwable) {
          // ignore
        }
      }
    }
    monitorThread?.start()
  }

  private fun stopMonitoring() {
    monitoring = false
    try {
      monitorThread?.interrupt()
    } catch (_: Exception) {
    }
    monitorThread = null
  }

  // ---------- Root detection (heuristic) ----------

  private fun isDeviceRooted(): Boolean {
    return checkTestKeys() || checkSuExists() || checkRootFiles()
  }

  private fun checkTestKeys(): Boolean {
    val tags = Build.TAGS
    return tags != null && tags.contains("test-keys")
  }

  private fun checkSuExists(): Boolean {
    return try {
      val process = Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
      val reader = BufferedReader(InputStreamReader(process.inputStream))
      val line = reader.readLine()
      reader.close()
      line != null
    } catch (e: Exception) {
      false
    }
  }

  private fun checkRootFiles(): Boolean {
    val paths = arrayOf(
      "/system/app/Superuser.apk",
      "/sbin/su",
      "/system/bin/su",
      "/system/xbin/su",
      "/data/local/xbin/su",
      "/data/local/bin/su",
      "/system/sd/xbin/su",
      "/system/bin/failsafe/su",
      "/data/local/su"
    )
    return paths.any { path ->
      try {
        File(path).exists()
      } catch (_: Exception) {
        false
      }
    }
  }

  // ---------- Hook / Frida/Xposed detection (heuristic) ----------

  private fun isHookFrameworkPresent(): Boolean {
    try {
      // Xposed marker
      val xposedFiles = arrayOf(
        "/system/framework/XposedBridge.jar",
        "/system/lib/libxposed_art.so",
        "/system/lib64/libxposed_art.so"
      )
      if (xposedFiles.any { File(it).exists() }) return true

      // Frida marker
      val fridaFiles = arrayOf(
        "/data/local/tmp/frida-server",
        "/data/local/tmp/re.frida.server"
      )
      if (fridaFiles.any { File(it).exists() }) return true
    } catch (_: Exception) {
    }
    return false
  }

  // ---------- Remote control apps detection ----------

  private fun detectRemoteControlApp(): String? {
    val ctx = applicationContext ?: return null
    val pm = ctx.packageManager

    val remotePkgs = listOf(
      "com.teamviewer.teamviewer.market.mobile",
      "com.teamviewer.quicksupport.market",
      "com.anydesk.anydeskandroid",
      "com.realvnc.viewer.android",
      "com.rsupport.rs.activity.rsupport.aos",
      "com.rsupport.mvagent" ,
      "com.splashtop.remote.skytap",
      "com.zoho.assist",
      "com.chrome.remoteDesktop"
    )

    for (pkg in remotePkgs) {
      try {
        pm.getPackageInfo(pkg, 0)
        return pkg
      } catch (_: PackageManager.NameNotFoundException) {
        // not installed
      } catch (_: Exception) {
      }
    }
    return null
  }

  // ---------- External display / cast detection ----------

  private fun isExternalDisplayConnected(): Boolean {
    val ctx = applicationContext ?: return false
    return try {
      val dm = ctx.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
      val displays = dm.displays
      displays != null && displays.size > 1
    } catch (_: Exception) {
      false
    }
  }

  // ---------- Overlay implementation (จอดำ + ข้อความเตือน) ----------

  private fun showOverlay() {
    val act = activity ?: return
    act.runOnUiThread {
      val root = act.window?.decorView as? ViewGroup ?: return@runOnUiThread

      if (overlayView == null) {
        val container = FrameLayout(act)
        container.setBackgroundColor(0xFF000000.toInt()) // ดำสนิท
        container.layoutParams = ViewGroup.LayoutParams(
          ViewGroup.LayoutParams.MATCH_PARENT,
          ViewGroup.LayoutParams.MATCH_PARENT
        )

        val tv = TextView(act)
        tv.text = "ไม่อนุญาตให้บันทึกหน้าจอหรือแชร์หน้าจอ\nระหว่างใช้งานแอปนี้"
        tv.setTextColor(0xFFFFFFFF.toInt())
        tv.textSize = 18f
        tv.textAlignment = View.TEXT_ALIGNMENT_CENTER
        tv.layoutParams = FrameLayout.LayoutParams(
          ViewGroup.LayoutParams.MATCH_PARENT,
          ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
          topMargin = 0
          marginStart = 32
          marginEnd = 32
          gravity = android.view.Gravity.CENTER
        }

        container.addView(tv)
        container.isClickable = true
        container.isFocusable = true

        overlayView = container
        root.addView(container)
      } else {
        overlayView?.visibility = View.VISIBLE
      }
    }
  }

  private fun hideOverlay() {
    val act = activity ?: return
    act.runOnUiThread {
      overlayView?.visibility = View.GONE
    }
  }

  // ---------- EventChannel ----------

  private fun sendEvent(map: Map<String, Any>) {
    eventSink?.success(map)
  }

  override fun onListen(arguments: Any?, events: EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }
}
