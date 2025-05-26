package com.melihhakanpektas.flutter_midi_pro

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import android.media.AudioManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  companion object {
    init {
      System.loadLibrary("native-lib")
    }
    @JvmStatic
    private external fun loadSoundfont(path: String, bank: Int, program: Int): Int

    @JvmStatic
    private external fun selectInstrument(sfId: Int, channel:Int, bank: Int, program: Int)

    @JvmStatic
    private external fun playNote(channel: Int, key: Int, velocity: Int, sfId: Int)

    @JvmStatic
    private external fun stopNote(channel: Int, key: Int, sfId: Int)

    @JvmStatic
    private external fun stopAllNotes(sfId: Int)

    @JvmStatic
    private external fun unloadSoundfont(sfId: Int)
    @JvmStatic
    private external fun dispose()
  }

  private lateinit var channel : MethodChannel
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
  private val TAG = "FlutterMidiProPlugin_FORK";

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }  
 override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "loadSoundfont" -> {
        val path = call.argument<String>("path") ?: ""
        val bank = call.argument<Int>("bank") ?: 0
        val program = call.argument<Int>("program") ?: 0

        // Force native call to run on main thread
        android.os.Handler(android.os.Looper.getMainLooper()).post {
          try {
            val audioManager = flutterPluginBinding.applicationContext
              .getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)

            Log.d(TAG, "Calling native loadSoundfont...")
            val sfId = loadSoundfont(path, bank, program)
            Log.d(TAG, "Native loadSoundfont finished. sfId: $sfId")

            audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)

            if (sfId == -1) {
              result.error("INVALID_ARGUMENT", "Failed to load soundfont at: $path", null)
            } else {
              result.success(sfId)
            }
          } catch (e: Exception) {
            result.error("LOAD_ERROR", e.message, null)
          }
        }
      }
      "selectInstrument" -> {
        val sfId = call.argument<Int>("sfId")?:1
        val channel = call.argument<Int>("channel")?:0
        val bank = call.argument<Int>("bank")?:0
        val program = call.argument<Int>("program")?:0
          selectInstrument(sfId, channel, bank, program)
          result.success(null)
        }
      "playNote" -> {
        val channel = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        val velocity = call.argument<Int>("velocity")
        val sfId = call.argument<Int>("sfId")
        if (channel != null && key != null && velocity != null && sfId != null) {
          playNote(channel, key, velocity, sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel, key, and velocity are required", null)
        }
      }
      "stopNote" -> {
        val channel = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        val sfId = call.argument<Int>("sfId")
        if (channel != null && key != null && sfId != null) {
          stopNote(channel, key, sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel and key are required", null)
        }
      }
      "stopAllNotes" -> {
        val sfId = call.argument<Int>("sfId") as Int
        stopAllNotes(sfId)
        result.success(null)
      }
      "unloadSoundfont" -> {
        val sfId = call.argument<Int>("sfId")
        if (sfId != null) {
          unloadSoundfont(sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "sfId is required", null)
        }
      }
      "dispose" -> {
        dispose()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}