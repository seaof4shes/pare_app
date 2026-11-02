package com.example.pare_app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Android owns the job lifetime; no Activity is required for SMS inference. */
class SmsAnalysisJob : JobService() {
    private var engine: FlutterEngine? = null
    private var parameters: JobParameters? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finish(true) }

    override fun onStartJob(params: JobParameters): Boolean {
        parameters = params
        running = true
        handler.post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val worker = FlutterEngine(applicationContext)
                engine = worker
                MethodChannel(worker.dartExecutor.binaryMessenger, "pare_app/sms_background")
                    .setMethodCallHandler { call, reply ->
                        try {
                            when (call.method) {
                                "pending" -> reply.success(SmsEventHandler.pending(applicationContext))
                                "acknowledge" -> {
                                    SmsEventHandler.acknowledge(applicationContext, call.argument<String>("id") ?: "")
                                    reply.success(true)
                                }
                                "finished" -> {
                                    reply.success(true)
                                    val retry = call.argument<Boolean>("retry") == true
                                    handler.post { finish(retry) }
                                }
                                else -> reply.notImplemented()
                            }
                        } catch (_: Exception) {
                            reply.error("SMS_WORK_FAILED", "Pending SMS could not be processed", null)
                        }
                    }
                handler.postDelayed(timeout, 120_000)
                worker.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(),
                        "package:pare_app/services/background_sms_worker.dart", "runBackgroundSms")
                )
            } catch (_: Exception) { finish(true) }
        }
        return true
    }

    private fun finish(retry: Boolean) {
        val params = parameters ?: return
        parameters = null
        handler.removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        running = false
        jobFinished(params, retry)
        // Messages can arrive after the worker took its queue snapshot.
        if (!retry) handler.postDelayed({ schedule(applicationContext) }, 500)
    }

    override fun onStopJob(params: JobParameters): Boolean {
        parameters = null
        handler.removeCallbacksAndMessages(null)
        engine?.destroy()
        engine = null
        running = false
        return true
    }

    companion object {
        const val JOB_ID = 72401
        private var running = false
        fun isRunning(): Boolean = running
        fun schedule(context: Context) {
            if (running) return
            val settings = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            if (!settings.getBoolean("flutter.protection_activated", false) ||
                !settings.getBoolean("flutter.isLoggedIn", false) ||
                !settings.getBoolean("flutter.msg_detection", true)) return
            try {
                if (SmsEventHandler.pending(context).isEmpty()) return
                val scheduler = context.getSystemService(JobScheduler::class.java)
                if (scheduler.getPendingJob(JOB_ID) != null) return
                scheduler.schedule(JobInfo.Builder(JOB_ID, ComponentName(context, SmsAnalysisJob::class.java))
                    .setMinimumLatency(0)
                    .setOverrideDeadline(0)
                    .setPersisted(true)
                    .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                    .build())
            } catch (_: Exception) {
                android.util.Log.w("PARE", "SMS job scheduling unavailable; encrypted queue retained")
            }
        }
    }
}
