package com.pkbstudio.pkbscreenguard

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.hardware.display.DisplayManager
import android.os.Build
import android.provider.Settings
import android.view.MotionEvent
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

class PkbScreenGuardPlugin : FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventSink? = null

    private var overlayView: View? = null

    @Volatile
    private var monitoring = false
    private var monitorThread: Thread? = null

    @Volatile
    private var lastTouchObscured: Boolean = false

    // ------------------------------------------------------------------------
    // FlutterPlugin
    // ------------------------------------------------------------------------

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel =
            MethodChannel(binding.binaryMessenger, "pkb_screen_guard/methods")
        methodChannel.setMethodCallHandler(this)

        eventChannel =
            EventChannel(binding.binaryMessenger, "pkb_screen_guard/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        applicationContext = null
    }

    // ------------------------------------------------------------------------
    // ActivityAware
    // ------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        attachRootTouchListener()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        attachRootTouchListener()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // ------------------------------------------------------------------------
    // MethodChannel
    // ------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "enableSecure" -> {
                runOnUi { act ->
                    act.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }

            "disableSecure" -> {
                runOnUi { act ->
                    act.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
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

            "enableSecurityGuard" -> {
                runOnUi { act ->
                    applySecurityGuard(act)
                }
                result.success(null)
            }

            "checkOverlayStatus" -> {
                result.success(
                    mapOf(
                        "hasOverlay" to isDisplayOverAppsEnabled(),
                        "touchObscured" to lastTouchObscured
                    )
                )
            }

            "checkAccessibilityServices" -> {
                val args = call.arguments as? Map<*, *>
                val installers =
                    (args?.get("allowedInstallers") as? List<*>)?.mapNotNull { it?.toString() }
                        ?: emptyList()
                val packages =
                    (args?.get("allowedPackages") as? List<*>)?.mapNotNull { it?.toString() }
                        ?: emptyList()

                result.success(checkAasSuspicious(installers, packages))
            }

            // ✅ เพิ่มใหม่
            "checkRemoteActive" -> {
                result.success(checkRemoteActive())
            }

            else -> result.notImplemented()
        }
    }

    private fun runOnUi(block: (Activity) -> Unit) {
        val act = activity ?: return
        act.runOnUiThread { block(act) }
    }

    // ------------------------------------------------------------------------
    // Security Guard
    // ------------------------------------------------------------------------

    private fun applySecurityGuard(act: Activity) {
        act.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            act.window.setHideOverlayWindows(true)
        }

        val rootView = act.window.decorView.rootView
        setFilterTouchesRecursive(rootView)
        attachRootTouchListener()
    }

    private fun attachRootTouchListener() {
        val act = activity ?: return
        val rootView = act.window.decorView.rootView

        rootView.setOnTouchListener { _, event ->
            event?.let { lastTouchObscured = isMotionEventObscured(it) }
            false
        }
    }

    private fun setFilterTouchesRecursive(view: View?) {
        if (view == null) return
        view.filterTouchesWhenObscured = true
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                setFilterTouchesRecursive(view.getChildAt(i))
            }
        }
    }

    private fun isMotionEventObscured(ev: MotionEvent): Boolean {
        val flags = ev.flags
        return (flags and MotionEvent.FLAG_WINDOW_IS_OBSCURED) != 0 ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                        (flags and MotionEvent.FLAG_WINDOW_IS_PARTIALLY_OBSCURED) != 0)
    }

    private fun isDisplayOverAppsEnabled(): Boolean {
        val ctx = applicationContext ?: return false
        return Settings.canDrawOverlays(ctx)
    }

    // ------------------------------------------------------------------------
    // Monitoring
    // ------------------------------------------------------------------------

    private fun startMonitoring() {
        if (monitoring) return
        monitoring = true

        monitorThread = Thread {
            var lastRemotePkg: String? = null

            while (monitoring) {
                try {
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
                            showOverlay()
                        }
                    }
                    Thread.sleep(1500)
                } catch (_: Exception) {
                }
            }
        }
        monitorThread?.start()
    }

    private fun stopMonitoring() {
        monitoring = false
        monitorThread?.interrupt()
        monitorThread = null
    }

    // ------------------------------------------------------------------------
    // Root
    // ------------------------------------------------------------------------

    private fun isDeviceRooted(): Boolean {
        return Build.TAGS?.contains("test-keys") == true ||
                File("/system/xbin/su").exists()
    }

    // ------------------------------------------------------------------------
    // Remote / Cast
    // ------------------------------------------------------------------------

//    private val remotePkgs = listOf(
//        "com.teamviewer.teamviewer.market.mobile",
//        "com.teamviewer.quicksupport.market",
//        "com.anydesk.anydeskandroid",
//        "com.realvnc.viewer.android",
//        "com.rsupport.rs.activity.rsupport.aos",
//        "com.rsupport.mvagent",
//        "com.splashtop.remote.skytap",
//        "com.zoho.assist",
//        "com.chrome.remoteDesktop"
//    )
    private val remotePkgs = listOf(

        // -----------------------------
        // TeamViewer
        // -----------------------------
        "com.teamviewer.teamviewer.market.mobile",
        "com.teamviewer.quicksupport.market",
        "com.teamviewer.host.market",

        // -----------------------------
        // AnyDesk
        // -----------------------------
        "com.anydesk.anydeskandroid",

        // -----------------------------
        // Chrome / Google
        // -----------------------------
        "com.chrome.remoteDesktop",

        // -----------------------------
        // VNC / Desktop
        // -----------------------------
        "com.realvnc.viewer.android",
        "com.microsoft.rdc.androidx",        // Microsoft Remote Desktop

        // -----------------------------
        // RSupport
        // -----------------------------
        "com.rsupport.rs.activity.rsupport.aos",
        "com.rsupport.mvagent",

        // -----------------------------
        // Splashtop
        // -----------------------------
        "com.splashtop.remote.skytap",
        "com.splashtop.personal",

        // -----------------------------
        // Zoho
        // -----------------------------
        "com.zoho.assist",

        // -----------------------------
        // BeyondTrust / Bomgar
        // -----------------------------
        "com.bomgar.android",

        // -----------------------------
        // ISL Online
        // -----------------------------
        "com.islonline",

        // -----------------------------
        // Supremo
        // -----------------------------
        "com.supremocontrol.supremo",

        // -----------------------------
        // Mikogo
        // -----------------------------
        "com.mikogo.remote",

        // -----------------------------
        // Remote Utilities
        // -----------------------------
        "com.remoteutilities.viewer",

        // -----------------------------
        // AirDroid (remote + mirror)
        // -----------------------------
        "com.airdroid.web",
        "com.airdroid.cast",

        // -----------------------------
        // Screen Mirroring / Cast (นิยมใช้โกง)
        // -----------------------------
        "com.apowersoft.mirror",
        "com.apowersoft.mirror.free",
        "com.lespark.mirror",
        "com.letsview.letsview",
        "com.vysor",
        "com.koushikdutta.vysor"
    )

    private fun detectRemoteControlApp(): String? {
        val pm = applicationContext?.packageManager ?: return null
        for (pkg in remotePkgs) {
            try {
                pm.getPackageInfo(pkg, 0)
                return pkg
            } catch (_: Exception) {
            }
        }
        return null
    }

    private fun isExternalDisplayConnected(): Boolean {
        val ctx = applicationContext ?: return false
        val dm = ctx.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        return dm.displays.size > 1
    }

    // ------------------------------------------------------------------------
    // ✅ checkRemoteActive (manual)
    // ------------------------------------------------------------------------

    private fun checkRemoteActive(): Map<String, Any> {
        val ctx = applicationContext ?: return mapOf("remoteActive" to false)
        val pm = ctx.packageManager

        var foundPkg: String? = null
        for (pkg in remotePkgs) {
            try {
                pm.getPackageInfo(pkg, 0)
                foundPkg = pkg
                break
            } catch (_: Exception) {
            }
        }

        if (foundPkg == null) {
            return mapOf("remoteActive" to false)
        }

        val enabledServices = Settings.Secure.getString(
            ctx.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: ""

        val accessibilityEnabled = enabledServices.contains(foundPkg)
        val externalDisplay = isExternalDisplayConnected()

        return mapOf(
            "remoteActive" to (accessibilityEnabled || externalDisplay),
            "remotePackage" to foundPkg,
            "accessibilityEnabled" to accessibilityEnabled,
            "externalDisplay" to externalDisplay
        )
    }

    // ------------------------------------------------------------------------
    // Overlay
    // ------------------------------------------------------------------------

    private fun showOverlay() {
        val act = activity ?: return
        act.runOnUiThread {
            val root = act.window.decorView as ViewGroup

            if (overlayView == null) {
                val container = FrameLayout(act)
                container.setBackgroundColor(0xFF000000.toInt())
                container.layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )

                val tv = TextView(act)
                tv.text = "ไม่อนุญาตให้บันทึกหรือควบคุมหน้าจอ"
                tv.setTextColor(0xFFFFFFFF.toInt())
                tv.textSize = 18f
                tv.textAlignment = View.TEXT_ALIGNMENT_CENTER
                tv.gravity = android.view.Gravity.CENTER

                val lp = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT
                )
                lp.gravity = android.view.Gravity.CENTER
                lp.marginStart = 32
                lp.marginEnd = 32

                tv.layoutParams = lp

                container.addView(tv)
                overlayView = container
                root.addView(container)
            } else {
                overlayView?.visibility = View.VISIBLE
            }
        }
    }
    private fun hideOverlay() {
        activity?.runOnUiThread {
            overlayView?.visibility = View.GONE
        }
    }

    // ------------------------------------------------------------------------
    // AAS
    // ------------------------------------------------------------------------

    private fun checkAasSuspicious(
        allowedInstallers: List<String>,
        allowedPackages: List<String>
    ): Map<String, Any> {
        return mapOf(
            "hasSuspiciousAas" to false,
            "suspiciousPackages" to emptyList<String>()
        )
    }

    // ------------------------------------------------------------------------
    // EventChannel
    // ------------------------------------------------------------------------

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
