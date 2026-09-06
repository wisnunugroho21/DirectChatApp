import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'chat_store.dart';

@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class PushService {
  final ChatStore chat;
  final Future<void> Function() recoverCall;
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _opened, _foreground;
  PushService(this.chat, this.recoverCall);
  static bool get supported =>
      kIsWeb ||
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  Future<void> enable() async {
    if (!supported) {
      throw StateError(
        'Push notifications are available on web, Android and iOS.',
      );
    }
    String? vapidKey;
    if (kIsWeb) {
      final config = await chat.api.request('GET', '/api/push/config');
      if (config['enabled'] != true) {
        throw StateError(
          'Configure Firebase on the backend and generate the web push config first.',
        );
      }
      vapidKey = config['vapidKey'] as String;
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: config['apiKey'],
            appId: config['appId'],
            messagingSenderId: config['messagingSenderId'],
            projectId: config['projectId'],
            authDomain: config['authDomain'],
            storageBucket: config['storageBucket'],
          ),
        );
      }
    } else if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    if (!kIsWeb) FirebaseMessaging.onBackgroundMessage(backgroundMessage);
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError('Notifications are disabled in device settings.');
    }
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
    final token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
    if (token == null) {
      throw StateError(
        'The notification token is not ready. Try again shortly.',
      );
    }
    await register(token);
    await _tokens?.cancel();
    await _opened?.cancel();
    await _foreground?.cancel();
    _tokens = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(chat.guard(() => register(token)));
    });
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(chat.guard(() => open(message)));
    });
    _foreground = FirebaseMessaging.onMessage.listen((message) {
      unawaited(chat.guard(chat.refresh));
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) await open(initial);
  }

  Future<void> register(String token) async {
    await chat.api.request('POST', '/api/push/devices', {
      'token': token,
      'platform': kIsWeb
          ? 'web'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
    });
    chat.deviceToken = token;
    if (chat.connection == 'Connected') {
      await chat.hub.invoke('BindDevice', args: [token]);
    }
  }

  Future<void> open(RemoteMessage message) async {
    if (message.data['type'] == 'call') {
      await recoverCall();
      return;
    }
    final sender = message.data['senderUsername'];
    if (sender != null) await chat.direct(sender);
  }

  Future<void> unregister() async {
    if (chat.deviceToken != null) {
      await chat.api.request('DELETE', '/api/push/devices', {
        'token': chat.deviceToken,
      });
      chat.deviceToken = null;
    }
  }

  void dispose() {
    unawaited(_tokens?.cancel());
    unawaited(_opened?.cancel());
    unawaited(_foreground?.cancel());
  }
}
