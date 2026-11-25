package com.qispine.poc.agora_poc

import android.os.Handler
import android.os.Looper
import android.os.Process
import io.agora.agora_rtc_ng.AgoraPIPFlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Agora's PiP controller needs this base class to receive the activity's
// picture-in-picture callbacks (plain FlutterActivity doesn't forward them).
class MainActivity : AgoraPIPFlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ONGOING_CALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            OngoingCallService.start(
                                this,
                                title = call.argument<String>("title").orEmpty(),
                                text = call.argument<String>("text").orEmpty(),
                            )
                            result.success(null)
                        }
                        "stop" -> {
                            OngoingCallService.stop(this)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    // e.g. Android refuses a foreground service started from
                    // the background; the call goes on without it.
                    result.error("ongoing_call_failed", error.message, null)
                }
            }
    }

    override fun onDestroy() {
        val isClosingApp = isFinishing && !isChangingConfigurations
        super.onDestroy()
        if (!isClosingApp) return
        OngoingCallService.stop(this)
        // The Agora engine lives in native code, outside this activity. If
        // the app is closed (swiped from recents, Back out of the app) while
        // a foreground service such as screen sharing keeps the process
        // alive, the call would carry on with no screen: camera, mic and
        // screen still sent, and reopening fails because the old engine is
        // still running. Ending the process ends the call. The short delay
        // lets a leave that is already in flight (e.g. PiP closed) go out.
        Handler(Looper.getMainLooper()).postDelayed(
            { Process.killProcess(Process.myPid()) },
            LEAVE_GRACE_MS,
        )
    }

    private companion object {
        const val LEAVE_GRACE_MS = 1000L
        const val ONGOING_CALL_CHANNEL = "qispine.poc/ongoing_call"
    }
}
