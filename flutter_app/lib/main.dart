import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';
import 'package:just_audio/just_audio.dart';
import 'api.dart';
import 'app_theme.dart';
import 'legacy_icons.dart';
import 'ui_components.dart';
import 'chat_store.dart';
import 'call_service.dart';
import 'push_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Material Symbols Outlined',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
  });
  runApp(const ConnectApp());
}

class ConnectApp extends StatefulWidget {
  const ConnectApp({super.key});
  @override
  State<ConnectApp> createState() => _ConnectAppState();
}

class _ConnectAppState extends State<ConnectApp> {
  final api = Api();
  Json? user;
  bool starting = true;
  String? startupError;
  @override
  void initState() {
    super.initState();
    api.onUnauthorized = () {
      unawaited(logout());
    };
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      await api.restore();
      if (api.token != null) {
        user = Json.from(await api.request('GET', '/api/auth/me') as Map);
      }
    } catch (e) {
      startupError = e.toString();
    }
    if (mounted) setState(() => starting = false);
  }

  Future<void> loggedIn() async {
    final me = Json.from(await api.request('GET', '/api/auth/me') as Map);
    if (mounted) setState(() => user = me);
  }

  Future<void> logout() async {
    await api.clear();
    if (mounted) setState(() => user = null);
  }

  @override
  void dispose() {
    api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TMS Connect',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(Brightness.light),
    themeMode: ThemeMode.light,
    home: starting
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : user == null
        ? AuthScreen(api: api, onLogin: loggedIn, initialError: startupError)
        : ChatScreen(
            key: ValueKey(user!['username']),
            api: api,
            user: user!,
            onLogout: logout,
          ),
  );
}

class AuthScreen extends StatefulWidget {
  final Api api;
  final Future<void> Function() onLogin;
  final String? initialError;
  const AuthScreen({
    super.key,
    required this.api,
    required this.onLogin,
    this.initialError,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'username',
      'password',
      'confirmPassword',
      'fullName',
      'email',
      'nickname',
      'employeeId',
    ])
      key: TextEditingController(),
  };
  bool register = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    error = widget.initialError;
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await widget.api.request('POST', '/api/auth/register', {
          for (final key in [
            'username',
            'password',
            'confirmPassword',
            'fullName',
            'email',
            'nickname',
          ])
            key: fields[key]!.text,
          'employeeId': int.tryParse(fields['employeeId']!.text),
        });
      }
      await widget.api.login(
        fields['username']!.text,
        fields['password']!.text,
      );
      await widget.onLogin();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(String key, String label, {bool optional = false}) {
    final password = key.toLowerCase().contains('password');
    final hint = switch (key) {
      'username' => 'Enter username',
      'password' => 'Enter password',
      'confirmPassword' => 'Confirm password',
      'fullName' => 'Enter your full name',
      'email' => 'Enter email',
      'employeeId' => 'Employee ID',
      _ => 'Nickname',
    };
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: LegacyStyle.border),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: key == 'confirmPassword' ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (register && !optional)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: Color(0xffdc3545)),
                    ),
                ],
              ),
            ),
          ),
          TextFormField(
            key: ValueKey(key),
            controller: fields[key],
            style: const TextStyle(
              fontFamily: 'Segoe UI',
              fontFamilyFallback: ['Arial'],
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.5,
              color: LegacyStyle.text,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: 'Segoe UI',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xff6c757d),
              ),
              border: border,
              enabledBorder: border,
              disabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: const BorderSide(
                  color: Color(0xff86b7fe),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            obscureText: password,
            enabled: !busy,
            autocorrect: !password,
            enableSuggestions: !password,
            autofillHints: switch (key) {
              'username' => const [AutofillHints.username],
              'password' => [
                register ? AutofillHints.newPassword : AutofillHints.password,
              ],
              'email' => const [AutofillHints.email],
              _ => null,
            },
            keyboardType: key == 'email'
                ? TextInputType.emailAddress
                : key == 'employeeId'
                ? TextInputType.number
                : TextInputType.text,
            onFieldSubmitted: (_) {
              if (!busy) unawaited(submit());
            },
            validator: (value) {
              if (!optional && (value == null || value.trim().isEmpty)) {
                return 'Required';
              }
              if (key == 'email' &&
                  !RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(value ?? '')) {
                return 'Enter a valid email';
              }
              if (key == 'employeeId' &&
                  value!.isNotEmpty &&
                  int.tryParse(value) == null) {
                return 'Enter a whole number';
              }
              if (register && key == 'password' && value!.length < 6) {
                return 'Use at least 6 characters';
              }
              if (key == 'confirmPassword' &&
                  value != fields['password']!.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    register: register,
    child: Form(
      key: form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              register ? 'Create Account' : 'Login',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              register
                  ? 'Join your team and keep every trip connected.'
                  : 'Welcome back. Your team is a message away.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: LegacyStyle.muted,
              ),
            ),
            const SizedBox(height: 24),
            if (error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xfff8d7da),
                  border: Border.all(color: const Color(0xfff1aeb5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: const TextStyle(color: Color(0xff58151c)),
                  ),
                ),
              ),
            if (register) ...[
              field('employeeId', 'Employee ID', optional: true),
              field('fullName', 'Full Name'),
              field('nickname', 'Nickname', optional: true),
            ],
            field('username', 'Username'),
            if (register) field('email', 'Email'),
            field('password', 'Password'),
            if (register) field('confirmPassword', 'Confirm Password'),
            LegacyButton(
              onPressed: busy ? null : submit,
              background: LegacyStyle.accent,
              height: 46,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                busy
                    ? 'Please wait…'
                    : register
                    ? 'Register'
                    : 'Login',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  register
                      ? 'Already have an account? '
                      : "New to TMS Connect? ",
                  style: TextStyle(
                    color: register
                        ? const Color(0xff6c757d)
                        : const Color(0xff212529),
                  ),
                ),
                LegacyButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          register = !register;
                          error = null;
                          form.currentState?.reset();
                        }),
                  radius: 0,
                  padding: EdgeInsets.zero,
                  foreground: const Color(0xff0d6efd),
                  child: Text(
                    register ? 'Login' : 'Register',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
  final Api api;
  final Json user;
  final Future<void> Function() onLogout;
  // The screen owns and disposes these services, including injected instances.
  final ChatStore? chatStore;
  final CallService? callService;
  const ChatScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
    this.chatStore,
    this.callService,
  });
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatStore chat;
  late final CallService call;
  late final PushService push;
  final composer = TextEditingController(), search = TextEditingController();
  final recorder = AudioRecorder();
  bool unread = false, sending = false, recording = false;
  int panel = 0;
  String? recordingConversation;
  String? noticeText;
  Timer? noticeTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chat = widget.chatStore ?? ChatStore(widget.api);
    call = widget.callService ?? CallService(chat);
    push = PushService(chat, recoverCall);
    chat.addListener(changed);
    call.addListener(changed);
    unawaited(
      run(() async {
        await call.init();
        await chat.start();
        await recoverCall();
        final sender = Uri.base.queryParameters['sender'];
        await chat.openNotification(
          conversationId: Uri.base.queryParameters['conversationId'],
          sender: sender,
        );
        if (const bool.fromEnvironment('ENABLE_PUSH')) await push.enable();
      }),
    );
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    final error = chat.error ?? call.error;
    chat.error = null;
    call.error = null;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) notice(error);
      });
    }
  }

  void notice(String text) {
    noticeTimer?.cancel();
    setState(() => noticeText = text);
    noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => noticeText = null);
    });
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) notice(e.toString());
    }
  }

  Future<void> recoverCall() async {
    if (call.peer != null || call.closing) return;
    final ringing = await widget.api.request('GET', '/api/calls/ringing');
    if (!mounted ||
        call.peer != null ||
        call.closing ||
        ringing['ringing'] != true) {
      return;
    }
    call.peer = ringing['callerUsername'];
    call.group = ringing['isGroup'] == true;
    call.groupId = ringing['groupCallId'];
    call.groupName = ringing['conversationName'];
    call.groupConversationId = ringing['conversationId'];
    call.video = ringing['callType'] == 'Video';
    call.incoming = true;
    call.status = 'Incoming call';
    call.ringTimeout();
    changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && chat.deviceToken != null) {
      unawaited(
        run(() async {
          await chat.hub.invoke('UnbindDevice');
        }),
      );
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(
        run(() async {
          await chat.reconnect();
          if (chat.deviceToken != null) {
            await chat.hub.invoke('BindDevice', args: [chat.deviceToken!]);
          }
          await recoverCall();
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chat.removeListener(changed);
    call.removeListener(changed);
    push.dispose();
    call.dispose();
    chat.dispose();
    composer.dispose();
    search.dispose();
    groupName.dispose();
    noticeTimer?.cancel();
    unawaited(recorder.dispose());
    super.dispose();
  }

  Future<void> send() async {
    if (sending || composer.text.trim().isEmpty) return;
    setState(() => sending = true);
    final text = composer.text;
    try {
      await chat.send(text);
      if (composer.text == text) composer.clear();
    } catch (e) {
      if (mounted) notice(e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> upload(
    Uint8List bytes,
    String name,
    String mime,
    String conversation,
  ) async {
    final message = await widget.api.upload(conversation, bytes, name, mime);
    chat.addMessage(message);
    await chat.refresh();
  }

  Future<void> attach() async {
    final conversation = chat.selected?['id'] as String?;
    if (conversation == null) return;
    final file = await FilePicker.pickFile();
    if (file == null) return;
    if (await file.length() > 25 * 1024 * 1024) {
      throw StateError('Files must be 25 MB or smaller.');
    }
    final bytes = await file.readAsBytes();
    const types = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'wav': 'audio/wav',
      'webm': 'audio/webm',
      'mp4': 'video/mp4',
    };
    await upload(
      bytes,
      file.name,
      types[file.extension?.toLowerCase()] ?? 'application/octet-stream',
      conversation,
    );
  }

  Future<void> voice() async {
    if (!recording) {
      if (call.peer != null) {
        throw StateError('Finish the call before recording a voice note.');
      }
      if (!await recorder.hasPermission()) {
        throw StateError('Microphone permission is required.');
      }
      recordingConversation = chat.selected!['id'] as String;
      final path = kIsWeb
          ? ''
          : '${(await getTemporaryDirectory()).path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(
        RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc),
        path: path,
      );
      if (mounted) setState(() => recording = true);
    } else {
      final path = await recorder.stop();
      if (mounted) setState(() => recording = false);
      if (path == null) throw StateError('No recording was created.');
      final bytes = await XFile(path).readAsBytes();
      await upload(
        bytes,
        kIsWeb ? 'voice-note.webm' : 'voice-note.m4a',
        kIsWeb ? 'audio/webm' : 'audio/mp4',
        recordingConversation!,
      );
    }
  }

  Future<void> cancelVoice() async {
    await recorder.cancel();
    if (mounted) setState(() => recording = false);
  }

  bool groupMode = false, creatingGroup = false;
  final groupName = TextEditingController();
  final selectedMembers = <String>{};
  void setGroupMode(bool value) => setState(() {
    groupMode = value;
    selectedMembers.clear();
    groupName.clear();
  });
  void toggleMember(String username) => setState(() {
    if (!selectedMembers.remove(username)) {
      if (selectedMembers.length >= 49) {
        notice('A group can have up to 50 members.');
        return;
      }
      selectedMembers.add(username);
    }
  });
  Widget groupFooter() => Container(
    padding: const EdgeInsets.fromLTRB(13, 10, 13, 13),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: LegacyStyle.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selectedMembers.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final username in selectedMembers)
                  Padding(
                    padding: const EdgeInsets.only(right: 7, bottom: 10),
                    child: LegacyButton(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      radius: 999,
                      background: LegacyStyle.soft,
                      foreground: const Color(0xff25496f),
                      onPressed: creatingGroup
                          ? null
                          : () => toggleMember(username),
                      child: Row(
                        children: [
                          Text(
                            chat.contacts.firstWhere(
                                      (c) => c['username'] == username,
                                      orElse: () => {},
                                    )['fullName']
                                    as String? ??
                                username,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 5),
                          const Icon(LegacyIcons.close, size: 17),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 45,
                child: LegacyFieldSurface(
                  child: TextField(
                    controller: groupName,
                    enabled: !creatingGroup,
                    maxLength: 80,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => unawaited(createGroup()),
                    decoration: const InputDecoration(
                      hintText: 'Group name',
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            LegacyIconButton(
              icon: creatingGroup ? LegacyIcons.refresh : LegacyIcons.send,
              tooltip: 'Create group',
              primary: true,
              size: 45,
              onPressed:
                  creatingGroup ||
                      selectedMembers.length < 2 ||
                      groupName.text.trim().isEmpty
                  ? null
                  : () => unawaited(createGroup()),
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> createGroup() async {
    if (creatingGroup ||
        selectedMembers.length < 2 ||
        groupName.text.trim().isEmpty) {
      return;
    }
    setState(() => creatingGroup = true);
    await run(() async {
      await chat.createGroup(groupName.text, selectedMembers.toList());
      if (mounted) {
        changePanel(0);
        notice('Group created.');
      }
    });
    if (mounted) setState(() => creatingGroup = false);
  }

  Widget avatar(String name) => ProfileAvatar(name: name);
  String name(Json c) => c['type'] == 'Group'
      ? c['name'] as String? ?? c['peerFullName'] as String? ?? 'Untitled group'
      : (c['peerFullName'] as String?)?.isNotEmpty == true
      ? c['peerFullName'] as String
      : c['peerUsername'] as String? ?? '';
  void changePanel(int value) => setState(() {
    panel = value;
    groupMode = false;
    selectedMembers.clear();
    groupName.clear();
    search.clear();
  });

  List<({String label, VoidCallback action})> accountMenu() => [
    (label: 'New chat', action: () => changePanel(1)),
    (label: 'Call history', action: () => changePanel(2)),
    (label: 'Refresh', action: () => unawaited(run(chat.reconnect))),
    (label: 'Mark all as read', action: () => unawaited(run(chat.markAllRead))),
    if (PushService.supported)
      (
        label: 'Enable notifications',
        action: () => unawaited(run(push.enable)),
      ),
    (
      label: 'Sign out',
      action: () => unawaited(
        run(() async {
          await call.end();
          try {
            await push.unregister();
          } finally {
            await widget.onLogout();
          }
        }),
      ),
    ),
  ];

  Widget sidebar() {
    final query = search.text.toLowerCase();
    final rows = panel == 1
        ? chat.contacts
              .where(
                (c) => '${c['fullName']} ${c['username']}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList()
        : chat.conversations
              .where(
                (c) =>
                    '${name(c)} ${c['lastMessage'] ?? ''}'
                        .toLowerCase()
                        .contains(query) &&
                    (!unread || (c['unread'] as num? ?? 0) > 0),
              )
              .toList();
    return ColoredBox(
      color: LegacyStyle.sidebar,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, bounds) => Container(
              height: LegacyStyle.headerHeight,
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width <= 420 ? 10 : 16,
              ),
              decoration: const BoxDecoration(
                color: Color(0xebffffff),
                border: Border(bottom: BorderSide(color: Color(0xffe8eef6))),
              ),
              child: Row(
                children: [
                  if (panel == 0) ...[
                    ProfileAvatar(
                      name: widget.user['username'] as String,
                      radius: 22,
                      profile: true,
                    ),
                    const SizedBox(width: 8),
                    if (MediaQuery.sizeOf(context).width > 360)
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TMS CONNECT',
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.08,
                              letterSpacing: 1.08,
                              fontWeight: FontWeight.w800,
                              color: LegacyStyle.accent,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Messages',
                            style: TextStyle(
                              fontSize: 17,
                              height: 1.08,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.34,
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    LegacyIconButton(
                      icon: LegacyIcons.phone_callback,
                      tooltip: 'Call History',
                      onPressed: () => changePanel(2),
                    ),
                    const SizedBox(width: 8),
                    LegacyIconButton(
                      icon: LegacyIcons.chat_add_on,
                      tooltip: 'New chat',
                      primary: true,
                      onPressed: () => changePanel(1),
                    ),
                    const SizedBox(width: 8),
                    LegacyMenu(
                      tooltip: 'Chat list options',
                      items: accountMenu(),
                    ),
                  ] else ...[
                    LegacyIconButton(
                      icon: LegacyIcons.arrow_left_alt,
                      tooltip: 'Back to chats',
                      onPressed: () => changePanel(0),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            panel == 1
                                ? (groupMode ? 'New group' : 'New chat')
                                : 'Call history',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.27,
                            ),
                          ),
                          Text(
                            panel == 1
                                ? (groupMode
                                      ? (selectedMembers.isEmpty
                                            ? 'Select at least 2 people'
                                            : '${selectedMembers.length} selected · 50 members max')
                                      : 'Pick someone to message')
                                : 'Incoming and outgoing calls',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: LegacyStyle.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (panel == 2)
                      LegacyIconButton(
                        icon: LegacyIcons.refresh,
                        tooltip: 'Refresh call history',
                        onPressed: () => unawaited(run(chat.refresh)),
                      )
                    else
                      LegacyMenu(
                        tooltip: 'New chat options',
                        items: [
                          (
                            label: groupMode
                                ? 'New direct chat'
                                : 'Create a group',
                            action: () => setGroupMode(!groupMode),
                          ),
                          (
                            label: 'Refresh',
                            action: () => unawaited(run(chat.refresh)),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (panel != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: SizedBox(
                height: 46,
                child: LegacyFieldSurface(
                  child: TextField(
                    controller: search,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: panel == 1
                          ? (groupMode
                                ? 'Search people'
                                : 'Search name or number')
                          : 'Search or start a new chat',
                      prefixIcon: const Icon(
                        LegacyIcons.search,
                        size: 21,
                        color: LegacyStyle.muted,
                      ),
                      suffixIcon: query.isEmpty
                          ? null
                          : LegacyIconButton(
                              icon: LegacyIcons.close,
                              tooltip: 'Clear search',
                              size: 28,
                              onPressed: () => setState(search.clear),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          if (panel == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
              child: Row(
                children: [
                  for (final filter in [false, true]) ...[
                    LegacyButton(
                      onPressed: () => setState(() => unread = filter),
                      background: unread == filter
                          ? LegacyStyle.soft
                          : LegacyStyle.sidebar,
                      foreground: unread == filter
                          ? LegacyStyle.accentDark
                          : LegacyStyle.muted,
                      radius: 999,
                      height: 34,
                      border: Border.all(
                        color: unread == filter
                            ? const Color(0xffbdd5ff)
                            : LegacyStyle.border,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 6,
                      ),
                      child: Text(
                        filter ? 'Unread' : 'All',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          if (panel == 1 &&
              !groupMode &&
              query.isEmpty &&
              chat.contacts.length >= 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: chatRow(
                label: 'Create a group',
                groupEntry: true,
                subtitle: 'Bring drivers and dispatchers together',
                leading: const ProfileAvatar(name: 'Group', group: true),
                trailing: const Icon(
                  LegacyIcons.chevron_right,
                  color: LegacyStyle.muted,
                ),
                onTap: () => setGroupMode(true),
              ),
            ),
          Expanded(
            child: panel == 2
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(9, 8, 9, 16),
                    children: [
                      if (chat.calls.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 52,
                          ),
                          child: Text(
                            'No calls yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: LegacyStyle.muted),
                          ),
                        ),
                      for (final c in chat.calls)
                        chatRow(
                          label: c['isGroup'] == true
                              ? c['conversationName'] as String? ?? 'Group call'
                              : c['peerUsername'] as String,
                          subtitle:
                              '${c['outgoing'] == true ? 'Outgoing' : 'Incoming'} · ${c['status']}${c['duration'] == null ? '' : ' · ${c['duration']} sec'}',
                          leading: ProfileAvatar(
                            name: c['peerUsername'] as String,
                            group: c['isGroup'] == true,
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                localTime(c['startDate']),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: LegacyStyle.muted,
                                ),
                              ),
                              Icon(
                                c['callType'] == 'Video'
                                    ? LegacyIcons.videocam
                                    : LegacyIcons.call,
                                size: 20,
                                color: LegacyStyle.accent,
                              ),
                            ],
                          ),
                          onTap: () => unawaited(
                            run(() async {
                              if (c['isGroup'] == true) {
                                await chat.openNotification(
                                  conversationId: c['conversationId'] as String,
                                );
                                await call.startConversation(
                                  chat.selected!,
                                  c['callType'] == 'Video',
                                );
                              } else {
                                await call.start(
                                  c['peerUsername'] as String,
                                  c['callType'] == 'Video',
                                );
                              }
                            }),
                          ),
                        ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(9, 2, 9, 14),
                    itemCount: rows.isEmpty ? 1 : rows.length,
                    itemBuilder: (_, i) {
                      if (rows.isEmpty) {
                        if (panel == 1) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 48,
                            ),
                            child: Text(
                              'No contacts found',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: LegacyStyle.muted),
                            ),
                          );
                        }
                        final filtered =
                            chat.conversations.isNotEmpty ||
                            query.isNotEmpty ||
                            unread;
                        return EmptyState(
                          icon: filtered
                              ? LegacyIcons.search_off
                              : LegacyIcons.forum,
                          title: filtered
                              ? 'No conversations found'
                              : 'Your inbox is ready',
                          description: filtered
                              ? 'Try another name or change the active filter.'
                              : 'Start a conversation with your dispatch team or another driver.',
                          action: filtered
                              ? null
                              : LegacyButton(
                                  onPressed: () => changePanel(1),
                                  background: LegacyStyle.accent,
                                  height: 42,
                                  child: const Text('Start a chat'),
                                ),
                        );
                      }
                      final c = rows[i];
                      final label = panel == 1
                          ? (c['fullName'] as String? ??
                                c['username'] as String)
                          : name(c);
                      final count = panel == 0 ? c['unread'] as num? ?? 0 : 0;
                      return chatRow(
                        label: label,
                        subtitle: panel == 1
                            ? '${c['username']} · ${c['status']}'
                            : c['lastMessage'] as String? ??
                                  'Start the conversation',
                        memberSelection: panel == 1 && groupMode,
                        selected: panel == 0
                            ? (c['id'] == chat.selected?['id'])
                            : groupMode &&
                                  selectedMembers.contains(c['username']),
                        leading: ProfileAvatar(
                          name: label,
                          group: panel == 0 && c['type'] == 'Group',
                          memberCount: panel == 0 && c['type'] == 'Group'
                              ? c['memberCount'] as int?
                              : null,
                          colorKey:
                              (panel == 1 ? c['username'] : c['peerUsername'])
                                  as String?,
                          online:
                              (panel == 1 ? c['status'] : c['peerStatus']) ==
                              'Online',
                        ),
                        trailing: panel == 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    messageTime(c['lastMessageAt']),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: count > 0
                                          ? LegacyStyle.accent
                                          : LegacyStyle.muted,
                                    ),
                                  ),
                                  if (count > 0) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 20,
                                      ),
                                      height: 20,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: LegacyStyle.accent,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : groupMode
                            ? Icon(
                                selectedMembers.contains(c['username'])
                                    ? LegacyIcons.check_circle
                                    : LegacyIcons.radio_button_unchecked,
                                color: selectedMembers.contains(c['username'])
                                    ? LegacyStyle.accent
                                    : LegacyStyle.muted,
                              )
                            : null,
                        onTap: () => unawaited(
                          run(() async {
                            if (panel == 1 && groupMode) {
                              if (!creatingGroup) {
                                toggleMember(c['username'] as String);
                              }
                              return;
                            }
                            if (recording) await cancelVoice();
                            composer.clear();
                            if (panel == 1) {
                              await chat.direct(c['username'] as String);
                              if (mounted) changePanel(0);
                            } else {
                              await chat.open(c);
                            }
                          }),
                        ),
                      );
                    },
                  ),
          ),
          if (panel == 1 && groupMode) groupFooter(),
          if (chat.connection != 'Connected')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              color: LegacyStyle.soft,
              child: Row(
                children: [
                  const Icon(
                    LegacyIcons.circle,
                    size: 7,
                    color: LegacyStyle.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chat.connection,
                      style: const TextStyle(
                        fontSize: 12,
                        color: LegacyStyle.muted,
                      ),
                    ),
                  ),
                  LegacyIconButton(
                    icon: LegacyIcons.refresh,
                    tooltip: 'Reconnect and refresh',
                    size: 32,
                    onPressed: () => unawaited(run(chat.reconnect)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget chatRow({
    required String label,
    required String subtitle,
    required Widget leading,
    Widget? trailing,
    bool selected = false,
    bool memberSelection = false,
    bool groupEntry = false,
    required VoidCallback onTap,
  }) => CustomPaint(
    foregroundPainter: selected && !memberSelection
        ? const LegacySelectionMarker()
        : null,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: groupEntry
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xfff5f3ff), Color(0xffeef5ff)],
              ),
              border: Border.all(color: const Color(0xffddd6fe)),
              borderRadius: BorderRadius.circular(16),
            )
          : selected && memberSelection
          ? BoxDecoration(
              color: const Color(0xffeff6ff),
              border: Border.all(color: const Color(0xffbfdbfe)),
              borderRadius: BorderRadius.circular(16),
            )
          : selected
          ? BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xffe8f1ff), Color(0xfff2f6ff)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xffccddfb)),
              boxShadow: LegacyStyle.shadow,
            )
          : BoxDecoration(
              border: Border.all(color: Colors.transparent),
              borderRadius: BorderRadius.circular(16),
            ),
      child: LegacyButton(
        onPressed: onTap,
        hoverBackground: selected ? Colors.transparent : Colors.white,
        foreground: LegacyStyle.text,
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: LegacyStyle.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
      ),
    ),
  );

  Future<void> leaveConversation() async {
    final leave = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cancel',
      pageBuilder: (context, _, _) => Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: LegacyStyle.text,
              fontSize: 14.5,
              height: 1.4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Leave conversation?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This removes the conversation from your chat list.',
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    LegacyButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    LegacyButton(
                      onPressed: () => Navigator.pop(context, true),
                      background: LegacyStyle.danger,
                      child: const Text('Leave'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (leave == true) {
      await run(() async {
        if (recording) await cancelVoice();
        await chat.leave();
      });
    }
  }

  Widget conversation(bool wide) {
    final c = chat.selected;
    final enabled = c != null && !sending && chat.connection == 'Connected';
    return LegacyChatBackground(
      child: Column(
        children: [
          Container(
            height: 72,
            padding: EdgeInsets.symmetric(horizontal: wide ? 18 : 8),
            decoration: const BoxDecoration(
              color: Color(0xebffffff),
              border: Border(bottom: BorderSide(color: Color(0xffe3ebf5))),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0d17324d),
                  blurRadius: 18,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                if (!wide)
                  LegacyIconButton(
                    icon: LegacyIcons.arrow_left_alt,
                    tooltip: 'Back to conversations',
                    size: 38,
                    onPressed: () => unawaited(
                      run(() async {
                        if (recording) await cancelVoice();
                        chat.closeConversation();
                      }),
                    ),
                  ),
                ProfileAvatar(
                  name: c == null ? 'TMS' : name(c),
                  initials: c == null ? 'TMS' : null,
                  colorKey: c?['peerUsername'] as String?,
                  group: c?['type'] == 'Group',
                  radius: 22,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c == null ? 'Messages' : name(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.16,
                        ),
                      ),
                      Text(
                        c == null
                            ? 'Choose a conversation to get started'
                            : c['type'] == 'Group'
                            ? '${c['memberCount']} members'
                            : c['peerStatus'] == 'Online'
                            ? '● Online now'
                            : 'Available for messages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c?['peerStatus'] == 'Online'
                              ? const Color(0xff07835f)
                              : LegacyStyle.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: wide ? 14 : 8),
                LegacyIconButton(
                  icon: LegacyIcons.call,
                  tooltip: 'Voice call',
                  size: wide ? 42 : 38,
                  onPressed: c == null || recording
                      ? null
                      : () => unawaited(
                          run(() => call.startConversation(c, false)),
                        ),
                ),
                SizedBox(width: wide ? 14 : 8),
                LegacyIconButton(
                  icon: LegacyIcons.videocam,
                  tooltip: 'Video call',
                  size: wide ? 42 : 38,
                  onPressed: c == null || recording
                      ? null
                      : () => unawaited(
                          run(() => call.startConversation(c, true)),
                        ),
                ),
                SizedBox(width: wide ? 14 : 8),
                LegacyMenu(
                  tooltip: 'Chat options',
                  items: [
                    if (c != null)
                      (
                        label: 'Refresh',
                        action: () => unawaited(run(() => chat.open(c))),
                      ),
                    if (c != null)
                      (
                        label: c['type'] == 'Group'
                            ? 'Leave group'
                            : 'Leave conversation',
                        action: () => unawaited(leaveConversation()),
                      ),
                    (label: 'New chat', action: () => changePanel(1)),
                  ],
                ),
              ],
            ),
          ),
          if (chat.loading)
            const SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                color: LegacyStyle.accent,
                backgroundColor: LegacyStyle.soft,
              ),
            ),
          Expanded(
            child: c == null
                ? LegacyWelcome(onNewChat: () => changePanel(1))
                : LayoutBuilder(
                    builder: (context, bounds) => Align(
                      alignment: Alignment.topCenter,
                      child: ListView.builder(
                        shrinkWrap: true,
                        reverse: true,
                        padding: EdgeInsets.fromLTRB(
                          wide
                              ? (MediaQuery.sizeOf(context).width * .06).clamp(
                                  18,
                                  84,
                                )
                              : bounds.maxWidth * .04,
                          wide ? 22 : 16,
                          wide
                              ? (MediaQuery.sizeOf(context).width * .06).clamp(
                                  18,
                                  84,
                                )
                              : bounds.maxWidth * .04,
                          wide ? 26 : 20,
                        ),
                        itemCount: chat.messages.length + 1,
                        itemBuilder: (_, index) {
                          if (index == chat.messages.length) {
                            return Column(
                              children: [
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xd9ffffff),
                                    border: Border.all(
                                      color: const Color(0xffdfe8f2),
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: LegacyStyle.shadow,
                                  ),
                                  child: Text(
                                    chat.messages.isEmpty
                                        ? 'TODAY'
                                        : conversationDate(
                                            chat.messages.first['createdAt'],
                                          ),
                                    style: const TextStyle(
                                      fontSize: 12.2,
                                      letterSpacing: .3,
                                      color: LegacyStyle.muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (chat.hasOlder && chat.messages.isNotEmpty)
                                  LegacyButton(
                                    onPressed: chat.loading
                                        ? null
                                        : () => unawaited(run(chat.older)),
                                    foreground: LegacyStyle.accent,
                                    child: const Text('Load older messages'),
                                  ),
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xebeff6ff),
                                    border: Border.all(
                                      color: const Color(0xffc9dcfd),
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        c['type'] == 'Group'
                                            ? LegacyIcons.groups
                                            : LegacyIcons.lock,
                                        size: 15,
                                        color: LegacyStyle.accentDark,
                                      ),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          c['type'] == 'Group'
                                              ? 'Messages are shared with group members.'
                                              : 'Messages are private and secure.',
                                          style: TextStyle(
                                            fontSize: 12.2,
                                            height: 1.5,
                                            fontWeight: FontWeight.w700,
                                            color: LegacyStyle.accentDark,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (chat.messages.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      26,
                                      0,
                                      18,
                                    ),
                                    child: Column(
                                      children: [
                                        ProfileAvatar(
                                          name: name(c),
                                          group: c['type'] == 'Group',
                                          colorKey:
                                              c['peerUsername'] as String?,
                                          radius: 36,
                                        ),
                                        const SizedBox(height: 13),
                                        Text(
                                          name(c),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          c['type'] == 'Group'
                                              ? 'This is the beginning of this group.'
                                              : 'This is the beginning of your conversation.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: LegacyStyle.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }
                          final m =
                              chat.messages[chat.messages.length - 1 - index];
                          return MessageBubble(
                            key: ValueKey(m['id']),
                            message: m,
                            group: c['type'] == 'Group',
                            firstInRun:
                                index == chat.messages.length - 1 ||
                                chat.messages[chat.messages.length -
                                        2 -
                                        index]['mine'] !=
                                    m['mine'] ||
                                chat.messages[chat.messages.length -
                                        2 -
                                        index]['sender'] !=
                                    m['sender'],
                            api: widget.api,
                            onError: notice,
                          );
                        },
                      ),
                    ),
                  ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 16 : 8,
              vertical: wide ? 11 : 9,
            ),
            decoration: const BoxDecoration(
              color: Color(0xebf8fbff),
              border: Border(top: BorderSide(color: Color(0xffdfe8f2))),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0a17324d),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: recording
                ? Container(
                    padding: const EdgeInsets.only(
                      left: 15,
                      right: 5,
                      top: 5,
                      bottom: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfffff7f7),
                      border: Border.all(color: const Color(0xfffecaca)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          LegacyIcons.circle,
                          size: 10,
                          color: Color(0xffef4444),
                        ),
                        const SizedBox(width: 11),
                        const Expanded(
                          child: Text(
                            'Recording voice note',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        LegacyIconButton(
                          icon: LegacyIcons.delete,
                          tooltip: 'Cancel voice note',
                          onPressed: () => unawaited(run(cancelVoice)),
                        ),
                        LegacyIconButton(
                          icon: LegacyIcons.send,
                          tooltip: 'Send voice note',
                          primary: true,
                          onPressed: () => unawaited(run(voice)),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      LegacyIconButton(
                        icon: LegacyIcons.attach_file,
                        tooltip: 'Attach file',
                        size: wide ? 42 : 40,
                        onPressed: enabled
                            ? () => unawaited(run(attach))
                            : null,
                      ),
                      SizedBox(width: wide ? 8 : 4),
                      Expanded(
                        child: LegacyFieldSurface(
                          radius: 16,
                          enabled: enabled,
                          child: TextField(
                            controller: composer,
                            enabled: enabled,
                            minLines: 1,
                            maxLines: 4,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => send(),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Type a message',
                              border: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                                borderSide: BorderSide(
                                  color: LegacyStyle.border,
                                ),
                              ),
                              enabledBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                                borderSide: BorderSide(
                                  color: LegacyStyle.border,
                                ),
                              ),
                              disabledBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                                borderSide: BorderSide(
                                  color: LegacyStyle.border,
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(16),
                                ),
                                borderSide: BorderSide(
                                  color: Color(0xff8db5f5),
                                ),
                              ),
                              fillColor: c == null
                                  ? const Color(0xfff3f6fa)
                                  : Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: wide ? 8 : 4),
                      if (composer.text.isEmpty)
                        LegacyIconButton(
                          icon: LegacyIcons.mic,
                          tooltip: 'Record voice message',
                          size: wide ? 42 : 40,
                          onPressed: enabled
                              ? () => unawaited(run(voice))
                              : null,
                        )
                      else
                        LegacyIconButton(
                          icon: LegacyIcons.send,
                          tooltip: 'Send message',
                          primary: true,
                          size: wide ? 42 : 40,
                          onPressed: enabled ? () => unawaited(send()) : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget callAction({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
    Color background = const Color(0x26ffffff),
    Color foreground = Colors.white,
  }) => SizedBox(
    width: 60,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LegacyIconButton(
          icon: icon,
          tooltip: tooltip,
          onPressed: onPressed,
          size: 52,
          radius: 26,
          background: background,
          foreground: foreground,
        ),
        const SizedBox(height: 9),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xffdbeafe), fontSize: 11.5),
        ),
      ],
    ),
  );

  Widget callControls() {
    final nativeSpeaker =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 12,
      children: [
        callAction(
          icon: call.muted ? LegacyIcons.mic_off : LegacyIcons.mic,
          label: call.muted ? 'Unmute' : 'Mute',
          tooltip: call.muted ? 'Unmute microphone' : 'Mute microphone',
          onPressed: call.mute,
          background: call.muted ? Colors.white : const Color(0x26ffffff),
          foreground: call.muted ? LegacyStyle.text : Colors.white,
        ),
        callAction(
          icon: call.video && call.camera
              ? LegacyIcons.videocam
              : LegacyIcons.videocam_off,
          label: 'Camera',
          tooltip: 'Toggle camera',
          onPressed: call.video ? call.toggleCamera : null,
        ),
        callAction(
          icon: LegacyIcons.volume_up,
          label: 'Speaker',
          tooltip: 'Speaker',
          onPressed: nativeSpeaker
              ? () => unawaited(run(call.toggleSpeaker))
              : null,
          background: call.speaker ? Colors.white : const Color(0x26ffffff),
          foreground: call.speaker ? LegacyStyle.text : Colors.white,
        ),
        callAction(
          icon: LegacyIcons.call_end,
          label: 'End',
          tooltip: 'End call',
          onPressed: () => unawaited(run(call.end)),
          background: LegacyStyle.danger,
        ),
      ],
    );
  }

  String get callTypeLabel =>
      '${call.group ? 'Group ' : ''}${call.video ? 'video' : 'voice'} call';

  Widget callIdentity({bool compact = false}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x12ffffff),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x24ffffff)),
        ),
        child: Text(
          call.incoming ? 'INCOMING CALL' : 'ONGOING CALL',
          style: const TextStyle(
            color: Color(0xffdbeafe),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ),
      if (!compact) ...[
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x0960a5fa),
            border: Border.all(color: const Color(0x4093c5fd)),
          ),
          child: ProfileAvatar(
            name: call.displayName,
            colorKey: call.displayName,
            group: call.group,
            radius: 64,
          ),
        ),
      ],
      SizedBox(height: compact ? 12 : 24),
      Text(
        call.displayName,
        textAlign: TextAlign.center,
        maxLines: compact ? 2 : null,
        overflow: compact ? TextOverflow.ellipsis : null,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 24 : 32,
          height: 1.15,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        callTypeLabel[0].toUpperCase() + callTypeLabel.substring(1),
        style: const TextStyle(color: Color(0xffbfdbfe), fontSize: 15),
      ),
      const SizedBox(height: 6),
      Text(
        call.incoming ? 'Waiting for you to answer' : call.status,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xff93aeca), fontSize: 13),
      ),
    ],
  );

  Widget callScreen({Widget? participants}) => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: bounds.maxHeight),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            callIdentity(),
            if (participants != null) ...[
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: participants,
              ),
            ],
            const SizedBox(height: 24),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LegacyIcons.lock, size: 14, color: Color(0xffa7f3d0)),
                SizedBox(width: 6),
                Text(
                  'Private and secure',
                  style: TextStyle(color: Color(0xffa7f3d0), fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 36),
            if (call.incoming)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 48,
                runSpacing: 12,
                children: [
                  callAction(
                    icon: LegacyIcons.call_end,
                    label: 'Decline',
                    tooltip: 'Decline call',
                    onPressed: () => unawaited(run(call.end)),
                    background: LegacyStyle.danger,
                  ),
                  callAction(
                    icon: LegacyIcons.call,
                    label: 'Accept',
                    tooltip: 'Accept call',
                    onPressed: call.accepting
                        ? null
                        : () => unawaited(run(call.accept)),
                    background: const Color(0xff16a34a),
                  ),
                ],
              )
            else
              callControls(),
          ],
        ),
      ),
    ),
  );

  Widget groupCallView() {
    final people =
        <({String name, RTCVideoRenderer renderer, bool camera, bool local})>[
          (name: 'You', renderer: call.local, camera: call.camera, local: true),
          for (final entry in call.participants.entries)
            (
              name: entry.key,
              renderer: entry.value.renderer,
              camera: entry.value.camera,
              local: false,
            ),
        ];
    Widget personTile(int index) {
      final person = people[index];
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xff102a43),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ProfileAvatar(
                    name: person.name,
                    colorKey: person.name,
                    radius: 34,
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Camera off',
                    style: TextStyle(color: Color(0xffa9c4df), fontSize: 12),
                  ),
                ],
              ),
            ),
            if (person.camera && person.renderer.srcObject != null)
              RTCVideoView(
                person.renderer,
                mirror: person.local,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            Positioned(
              left: 10,
              bottom: 9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xa8020b18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  person.name,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (call.video) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: callIdentity(compact: true),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 3 : 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: people.length,
              itemBuilder: (_, i) => personTile(i),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: callControls(),
          ),
        ],
      );
    }
    return callScreen(
      participants: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x0dffffff),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x24ffffff)),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final person in people)
              SizedBox(
                width: 74,
                child: Column(
                  children: [
                    ProfileAvatar(name: person.name, radius: 27, profile: true),
                    const SizedBox(height: 8),
                    Text(
                      person.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xffbfdbfe),
                      ),
                    ),
                    // Keep remote audio renderers mounted on web.
                    if (!person.local)
                      SizedBox(
                        width: 1,
                        height: 1,
                        child: RTCVideoView(person.renderer),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget callOverlay() => Positioned.fill(
    child: Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: call.incoming ? 'Incoming call' : 'Call',
      child: BlockSemantics(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xff153a68), Color(0xff07182b)],
            ),
          ),
          child: SafeArea(
            child: call.incoming
                ? callScreen()
                : call.group
                ? groupCallView()
                : call.video
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: RTCVideoView(
                          call.remote,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                      Positioned(
                        top: 24,
                        left: 24,
                        right: 24,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0x9907182b),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: callIdentity(compact: true),
                        ),
                      ),
                      Positioned(
                        bottom: 112,
                        right: 20,
                        width: 140,
                        height: 187,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: RTCVideoView(call.local, mirror: true),
                              ),
                              const Positioned(
                                left: 8,
                                bottom: 7,
                                child: Text(
                                  'You',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 24,
                        left: 16,
                        right: 16,
                        child: callControls(),
                      ),
                    ],
                  )
                : callScreen(),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth > LegacyStyle.mobileBreakpoint;
          return Stack(
            children: [
              if (wide)
                Row(
                  children: [
                    SizedBox(
                      width: LegacyStyle.sidebarWidth,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: LegacyStyle.border),
                          ),
                        ),
                        child: sidebar(),
                      ),
                    ),
                    Expanded(child: conversation(true)),
                  ],
                )
              else if (chat.selected == null || panel != 0)
                sidebar()
              else
                conversation(false),
              if (call.peer != null) callOverlay(),
              if (noticeText != null)
                Positioned(
                  bottom: call.peer != null ? 108 : 88,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xee102a43),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0x22ffffff)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24102a43),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          noticeText!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

String conversationDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  final now = DateTime.now();
  if (date == null ||
      (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day)) {
    return 'TODAY';
  }
  return '${date.day}/${date.month}/${date.year}';
}

String messageTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String localTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class MessageBubble extends StatefulWidget {
  final Json message;
  final Api api;
  final bool firstInRun;
  final bool group;
  final void Function(String) onError;
  const MessageBubble({
    super.key,
    required this.message,
    required this.api,
    this.firstInRun = true,
    this.group = false,
    required this.onError,
  });
  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? playback;
  Future<Uint8List>? preview;
  @override
  void initState() {
    super.initState();
    final a = widget.message['attachment'] as Map?;
    if (a != null &&
        [
          'image/png',
          'image/jpeg',
          'image/gif',
          'image/webp',
        ].contains(a['mimeType'])) {
      preview = widget.api.download(a['url'] as String).then((value) {
        bytes = value;
        return value;
      });
    }
  }

  AudioPlayer get player {
    if (_player == null) {
      _player = AudioPlayer();
      playback = _player!.playerStateStream.listen((state) {
        if (mounted) {
          setState(
            () => playing =
                state.playing &&
                state.processingState != ProcessingState.completed,
          );
        }
      });
    }
    return _player!;
  }

  Uint8List? bytes;
  bool busy = false, playing = false;
  @override
  void dispose() {
    unawaited(playback?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> attachment(bool play) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final a = widget.message['attachment'] as Map;
      bytes ??= await widget.api.download(a['url'] as String);
      if (!mounted) return;
      if (play) {
        if (playing) {
          await player.pause();
        } else {
          if (player.audioSource == null) {
            await player.setAudioSource(
              AudioSource.uri(
                Uri.dataFromBytes(bytes!, mimeType: a['mimeType'] as String),
              ),
            );
          }
          if (player.processingState == ProcessingState.completed) {
            await player.seek(Duration.zero);
          }
          unawaited(
            player.play().catchError((Object e) {
              if (mounted) widget.onError(e.toString());
            }),
          );
        }
        if (mounted) setState(() => playing = !playing);
      } else {
        await FilePicker.saveFile(
          fileName: a['fileName'] as String,
          bytes: bytes!,
          mimeType: a['mimeType'] as String,
        );
      }
    } catch (e) {
      if (mounted) widget.onError(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final mine = m['mine'] == true;
    final a = m['attachment'] as Map?;
    final audio = a != null && (a['mimeType'] as String).startsWith('audio/');
    final foreground = mine ? Colors.white : LegacyStyle.text;
    return LayoutBuilder(
      builder: (context, bounds) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: CustomPaint(
          foregroundPainter: LegacyBubbleTail(
            mine: mine,
            first: widget.firstInRun,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth:
                  (bounds.maxWidth *
                          (MediaQuery.sizeOf(context).width > 900 ? .76 : .85))
                      .clamp(0, 620),
            ),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 9),
            decoration: BoxDecoration(
              color: mine ? null : Colors.white,
              gradient: mine
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff3475ed), LegacyStyle.accent],
                    )
                  : null,

              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(!mine && widget.firstInRun ? 0 : 18),
                topRight: Radius.circular(mine && widget.firstInRun ? 0 : 18),
                bottomLeft: const Radius.circular(18),
                bottomRight: const Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: mine
                      ? const Color(0x262563eb)
                      : const Color(0x121f436d),
                  blurRadius: mine ? 18 : 16,
                  offset: Offset(0, mine ? 7 : 5),
                ),
              ],
            ),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.group && !mine && widget.firstInRun)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        m['sender'] as String? ?? 'Group member',
                        style: const TextStyle(
                          color: Color(0xff4f46e5),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (preview != null)
                    FutureBuilder<Uint8List>(
                      future: preview,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text(
                            'Image unavailable. Use Download to retry.',
                            style: TextStyle(color: foreground),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const SizedBox(
                            width: 180,
                            height: 100,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(
                            snapshot.data!,
                            width: 260,
                            height: 180,
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, stack) => Text(
                              'Cannot preview this image.',
                              style: TextStyle(color: foreground),
                            ),
                          ),
                        );
                      },
                    ),
                  if (m['text'] != null && (m['text'] as String).isNotEmpty)
                    SelectableText(
                      m['text'] as String,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.48,
                        color: foreground,
                      ),
                    ),
                  if (a != null)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (audio)
                          LegacyIconButton(
                            tooltip: playing
                                ? 'Pause voice note'
                                : 'Play voice note',
                            onPressed: busy
                                ? null
                                : () => unawaited(attachment(true)),
                            icon: playing
                                ? LegacyIcons.pause
                                : LegacyIcons.play_arrow,
                            foreground: foreground,
                          ),
                        LegacyButton(
                          onPressed: busy
                              ? null
                              : () => unawaited(attachment(false)),
                          tooltip: 'Download attachment',
                          foreground: foreground,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LegacyIcons.download, size: 20),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  busy ? 'Loading…' : a['fileName'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        messageTime(m['createdAt']),
                        style: TextStyle(
                          fontSize: 11,
                          color: mine
                              ? const Color(0xffdbeafe)
                              : LegacyStyle.muted,
                        ),
                      ),
                      if (mine) ...[
                        const SizedBox(width: 3),
                        Semantics(
                          label: m['read'] == true ? 'Read' : 'Sent',
                          child: Icon(
                            m['read'] == true
                                ? LegacyIcons.done_all
                                : LegacyIcons.done,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
