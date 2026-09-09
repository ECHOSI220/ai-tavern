import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Nearby P2P_STAR keeps Wi-Fi state permissions on modern Android', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />',
      ),
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />',
      ),
    );
    expect(
      manifest,
      isNot(contains('ACCESS_WIFI_STATE" android:maxSdkVersion')),
    );
    expect(
      manifest,
      isNot(contains('CHANGE_WIFI_STATE" android:maxSdkVersion')),
    );
  });

  test('AOSP Wi-Fi Direct fallback declares its network capabilities', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.ACCESS_NETWORK_STATE'));
    expect(manifest, contains('android.permission.CHANGE_NETWORK_STATE'));
    expect(
      manifest,
      contains(
        'android.permission.NEARBY_WIFI_DEVICES" android:minSdkVersion="33"',
      ),
    );
    expect(
      manifest,
      contains('android.hardware.wifi.direct" android:required="false"'),
    );
    expect(
      manifest,
      matches(
        RegExp(
          r'android.permission.ACCESS_FINE_LOCATION"[^>]*android:maxSdkVersion="32"',
        ),
      ),
    );
  });

  test('Wi-Fi Direct bridge does not depend on Google Play services', () {
    final bridge = File(
      'android/app/src/main/kotlin/com/imaginary/tavern/ai_tavern/'
      'WifiDirectConnectionsBridge.kt',
    ).readAsStringSync();

    expect(bridge, contains('WifiP2pManager'));
    expect(bridge, contains('_aitavern._tcp'));
    expect(bridge, isNot(contains('com.google.android.gms')));
  });
}
