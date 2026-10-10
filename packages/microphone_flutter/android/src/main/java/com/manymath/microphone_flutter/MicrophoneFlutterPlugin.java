package com.manymath.microphone_flutter;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;

import androidx.annotation.NonNull;

import java.util.ArrayList;
import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Checks and requests the RECORD_AUDIO runtime permission for the native
 * capture library, which has no way to do either itself: asking needs the
 * app's Activity. Capture itself goes over FFI, not this channel.
 */
public final class MicrophoneFlutterPlugin
    implements FlutterPlugin,
        ActivityAware,
        MethodChannel.MethodCallHandler,
        PluginRegistry.RequestPermissionsResultListener {
  private static final String CHANNEL = "microphone_flutter";
  // Any app-unique value; it only routes the result back to this plugin.
  private static final int REQUEST_CODE = 0x6d63;

  private MethodChannel channel;
  private Context context;
  private ActivityPluginBinding activity;
  // Calls waiting on the one outstanding system prompt.
  private final List<MethodChannel.Result> pending = new ArrayList<>();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    channel = null;
    context = null;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activity = binding;
    binding.addRequestPermissionsResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    detachActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    detachActivity();
    // No Activity will deliver the answer now.
    answerPending(false);
  }

  private void detachActivity() {
    if (activity != null) {
      activity.removeRequestPermissionsResultListener(this);
      activity = null;
    }
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    switch (call.method) {
      case "hasPermission":
        result.success(granted());
        break;
      case "requestPermission":
        if (granted()) {
          result.success(true);
        } else if (activity == null) {
          // Without an Activity (e.g. a background engine) there is nothing
          // to show the prompt on.
          result.success(false);
        } else {
          pending.add(result);
          if (pending.size() == 1) {
            Activity host = activity.getActivity();
            host.requestPermissions(new String[] {Manifest.permission.RECORD_AUDIO}, REQUEST_CODE);
          }
        }
        break;
      default:
        result.notImplemented();
    }
  }

  @Override
  public boolean onRequestPermissionsResult(
      int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
    if (requestCode != REQUEST_CODE) return false;
    answerPending(grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
    return true;
  }

  private void answerPending(boolean grantedNow) {
    for (MethodChannel.Result result : pending) {
      result.success(grantedNow);
    }
    pending.clear();
  }

  private boolean granted() {
    return context != null
        && context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED;
  }
}
