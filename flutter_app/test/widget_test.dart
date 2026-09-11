import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tms_connect/api.dart';
import 'package:tms_connect/app_theme.dart';
import 'package:tms_connect/main.dart';
import 'package:tms_connect/ui_components.dart';
import 'package:tms_connect/chat_store.dart';
import 'package:tms_connect/call_service.dart';

class OfflineApi extends Api {
  @override
  Future<dynamic> request(String method, String path, [Object? body]) async => {
    'ringing': false,
  };
}

class PreviewStore extends ChatStore {
  PreviewStore(super.api) {
    connection = 'Connected';
    hasOlder = false;
    conversations = [
      {
        'id': 'dispatch',
        'peerUsername': 'jane',
        'peerFullName': 'Jane Cooper',
        'peerStatus': 'Online',
        'lastMessage': 'The documents are ready for your next trip.',
        'lastMessageAt': '2026-09-06T08:42:00Z',
        'unread': 2,
      },
      {
        'id': 'driver',
        'peerUsername': 'robert',
        'peerFullName': 'Robert Fox',
        'peerStatus': 'Offline',
        'lastMessage': 'Thanks, see you at the depot.',
        'lastMessageAt': '2026-09-06T08:20:00Z',
        'unread': 0,
      },
    ];
    contacts = [
      {'username': 'jane', 'fullName': 'Jane Cooper', 'status': 'Online'},
      {'username': 'robert', 'fullName': 'Robert Fox', 'status': 'Offline'},
    ];
  }
  @override
  Future<void> start() async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<void> open(Json conversation) async {
    selected = conversation;
    messages = [
      {
        'id': '1',
        'mine': false,
        'text': 'Hi Alex! The documents are ready for your next trip.',
        'createdAt': '2026-09-06T08:42:00Z',
      },
      {
        'id': '2',
        'mine': true,
        'text': 'Thanks, Jane. I’ll pick them up before heading out.',
        'createdAt': '2026-09-06T08:43:00Z',
        'read': true,
      },
    ];
    changed();
  }

  @override
  Future<void> createGroup(String name, List<String> usernames) async {
    expect(usernames, containsAll(['jane', 'robert']));
    final group = <String, dynamic>{
      'id': 'group',
      'type': 'Group',
      'name': name,
      'memberCount': 3,
      'unread': 0,
    };
    conversations.add(group);
    await open(group);
    messages = [
      {
        'id': 'g1',
        'sender': 'jane',
        'mine': false,
        'text': 'Welcome team',
        'createdAt': '2026-09-11T08:00:00Z',
      },
      {
        'id': 'g2',
        'sender': 'robert',
        'mine': false,
        'text': 'Ready for dispatch',
        'createdAt': '2026-09-11T08:01:00Z',
      },
    ];
    changed();
  }

  @override
  Future<void> direct(String username) => open(conversations.first);
  @override
  Future<void> send(String text) async {
    messages.add({
      'id': '3',
      'mine': true,
      'text': text,
      'createdAt': '2026-09-06T08:44:00Z',
    });
    changed();
  }
}

class PreviewCall extends CallService {
  PreviewCall(super.chat);
  @override
  Future<void> init() async {}
  @override
  Future<void> end({bool notifyPeer = true}) async {
    peer = null;
    incoming = false;
  }
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );

  boundary.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/ui-review')..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final font in [
      ('Roboto', const String.fromEnvironment('UI_FONT')),
      ('Segoe UI', const String.fromEnvironment('UI_AUTH_FONT')),
      ('LegacySymbols', 'assets/fonts/LegacySymbols.ttf'),
    ]) {
      if (font.$2.isEmpty) continue;
      final loader = FontLoader(font.$1)
        ..addFont(
          File(
            font.$2,
          ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      if (font.$1 == 'Segoe UI') {
        for (final path in [
          const String.fromEnvironment('UI_BOLD_FONT'),
          const String.fromEnvironment('UI_SEMIBOLD_FONT'),
        ]) {
          if (path.isNotEmpty) {
            loader.addFont(
              File(
                path,
              ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          }
        }
      }
      await loader.load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('FlutterWebRTC.Method'),
          (_) async => null,
        );
  });
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(900, 800),
    const Size(1280, 800),
  ]) {
    testWidgets('Legacy auth layout and validation at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_UI')) debugDisableShadows = false;
      final api = Api();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: AuthScreen(api: api, onLogin: () async {}),
          ),
        ),
      );
      expect(find.text('Welcome back.'), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      await capture(tester, 'login-${size.width.toInt()}');
      await tester.tap(find.widgetWithText(LegacyButton, 'Login'));
      await tester.pump();
      expect(find.text('Required'), findsNWidgets(2));
      await tester.enterText(find.byKey(const ValueKey('password')), 'secret');
      expect(
        tester.widget<TextFormField>(find.byKey(const ValueKey('password'))),
        isNotNull,
      );
      await tester.ensureVisible(find.text('Register'));
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(7));
      expect(find.text('Create Account'), findsOneWidget);
      await capture(tester, 'register-${size.width.toInt()}');
      await tester.ensureVisible(find.text('Register'));
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsNWidgets(5));
      debugDisableShadows = true;
      expect(tester.takeException(), isNull);
    });
    testWidgets('Legacy chat navigation, composer and call UI at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_UI')) debugDisableShadows = false;
      final api = OfflineApi();
      addTearDown(api.dispose);
      final store = PreviewStore(api);
      final call = PreviewCall(store);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: ChatScreen(
              api: api,
              user: const {'username': 'alex'},
              onLogout: () async {},
              chatStore: store,
              callService: call,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.text('Keep every trip connected'),
        size.width > 900 ? findsOneWidget : findsNothing,
      );
      await capture(tester, 'inbox-${size.width.toInt()}');
      await tester.tap(find.text('Unread'));
      await tester.pump();
      expect(find.text('Robert Fox'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.pump();
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();
      expect(find.text('Pick someone to message'), findsOneWidget);
      await capture(tester, 'contacts-${size.width.toInt()}');
      await tester.tap(find.text('Create a group'));
      await tester.pumpAndSettle();
      expect(find.text('Select at least 2 people'), findsOneWidget);
      expect(
        tester
            .widget<LegacyIconButton>(
              find.ancestor(
                of: find.byTooltip('Create group'),
                matching: find.byType(LegacyIconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Jane Cooper'));
      await tester.tap(find.text('Robert Fox'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Group name'),
        'Dispatch team',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'group-create-${size.width.toInt()}');
      await tester.tap(find.byTooltip('Create group'));
      await tester.pumpAndSettle();
      expect(find.text('3 members'), findsOneWidget);
      expect(
        find.text('Messages are shared with group members.'),
        findsOneWidget,
      );
      expect(find.text('jane'), findsOneWidget);
      expect(find.text('robert'), findsOneWidget);
      expect(
        tester
            .widgetList<MessageBubble>(find.byType(MessageBubble))
            .every((b) => b.firstInRun),
        isTrue,
      );
      await capture(tester, 'group-conversation-${size.width.toInt()}');
      store.closeConversation();
      store.conversations.removeWhere((c) => c['type'] == 'Group');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New chat'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to chats'));
      await tester.pump();
      await tester.tap(find.byTooltip('Call History'));
      await tester.pump();
      expect(find.text('Incoming and outgoing calls'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to chats'));
      await tester.pump();
      await tester.tap(find.text('Jane Cooper'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Record voice message'), findsOneWidget);
      await capture(tester, 'conversation-${size.width.toInt()}');
      final composer = find.widgetWithText(TextField, 'Type a message');
      await tester.enterText(composer, 'Ready to go');
      await tester.pump();
      expect(find.byTooltip('Record voice message'), findsNothing);
      await tester.tap(find.byTooltip('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to go'), findsOneWidget);
      expect(
        tester
            .widget<MessageBubble>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is MessageBubble && widget.message['id'] == '3',
              ),
            )
            .firstInRun,
        isFalse,
      );
      if (size.width <= 900) {
        await tester.tap(find.byTooltip('Back to conversations'));
        await tester.pumpAndSettle();
        expect(find.text('Robert Fox'), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Chat list options'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      await capture(tester, 'menu-${size.width.toInt()}');
      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      call.peer = 'Jane Cooper';
      call.status = 'Calling…';
      call.changed();
      await tester.pumpAndSettle();
      await capture(tester, 'voice-call-${size.width.toInt()}');
      expect(find.byTooltip('End call'), findsOneWidget);
      call.group = true;
      call.groupName = 'Dispatch team';
      call.status = 'Waiting for members…';
      call.changed();
      await tester.pumpAndSettle();
      expect(find.text('Group voice call'), findsOneWidget);
      await capture(tester, 'group-call-${size.width.toInt()}');
      call.video = true;
      call.changed();
      await tester.pumpAndSettle();
      expect(find.text('Camera off'), findsOneWidget);
      await capture(tester, 'group-video-${size.width.toInt()}');
      call.video = false;
      call.group = false;

      call.incoming = true;
      call.changed();
      await tester.pumpAndSettle();
      await capture(tester, 'incoming-call-${size.width.toInt()}');
      expect(find.byTooltip('Accept call'), findsOneWidget);
      debugDisableShadows = true;
      expect(tester.takeException(), isNull);
      call.peer = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
