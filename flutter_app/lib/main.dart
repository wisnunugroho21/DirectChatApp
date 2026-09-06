import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cross_file/cross_file.dart';
import 'package:just_audio/just_audio.dart';
import 'api.dart';
import 'chat_store.dart';
import 'call_service.dart';
import 'push_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff147d72)),
      scaffoldBackgroundColor: const Color(0xfff5f8f7),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
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

  Widget field(String key, String label, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      decoration: InputDecoration(labelText: label),
      obscureText: key.toLowerCase().contains('password'),
      enabled: !busy,
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
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value ?? '')) {
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
        if (key == 'confirmPassword' && value != fields['password']!.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.forum_rounded,
                  size: 58,
                  color: Color(0xff147d72),
                ),
                const SizedBox(height: 16),
                Text(
                  'TMS Connect',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    register
                        ? 'Create your account'
                        : 'Welcome back. Sign in to your conversations.',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (register) field('fullName', 'Full name'),
                field('username', register ? 'Username' : 'Username or email'),
                if (register) field('email', 'Email'),
                field('password', 'Password'),
                if (register) ...[
                  field('confirmPassword', 'Confirm password'),
                  field('nickname', 'Nickname (optional)', optional: true),
                  field('employeeId', 'Employee ID (optional)', optional: true),
                ],
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : register
                          ? 'Create account'
                          : 'Sign in',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          register = !register;
                          error = null;
                        }),
                  child: Text(
                    register
                        ? 'Already have an account? Sign in'
                        : 'Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
  final Api api;
  final Json user;
  final Future<void> Function() onLogout;
  const ChatScreen({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    chat = ChatStore(widget.api);
    call = CallService(chat);
    push = PushService(chat, recoverCall);
    chat.addListener(changed);
    call.addListener(changed);
    unawaited(
      run(() async {
        await call.init();
        await chat.start();
        await recoverCall();
        final sender = Uri.base.queryParameters['sender'];
        if (sender != null && sender.isNotEmpty) await chat.direct(sender);
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

  void notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) notice(e.toString());
    }
  }

  Future<void> recoverCall() async {
    if (call.peer != null) return;
    final ringing = await widget.api.request('GET', '/api/calls/ringing');
    if (ringing['ringing'] != true) return;
    call.peer = ringing['callerUsername'];
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

  Widget avatar(String name) => CircleAvatar(
    child: Text(
      name.isEmpty
          ? '?'
          : name.substring(0, name.length < 2 ? name.length : 2).toUpperCase(),
    ),
  );
  String name(Json c) => (c['peerFullName'] as String?)?.isNotEmpty == true
      ? c['peerFullName'] as String
      : c['peerUsername'] as String? ?? '';
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
                    (!unread || (c['unread'] as num) > 0),
              )
              .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
          child: Row(
            children: [
              avatar(widget.user['username'] as String),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TMS Connect'),
                    Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) => unawaited(
                  run(() async {
                    if (value == 'push') await push.enable();
                    if (value == 'logout') {
                      await call.end();
                      try {
                        await push.unregister();
                      } finally {
                        await widget.onLogout();
                      }
                    }
                  }),
                ),
                itemBuilder: (_) => [
                  if (PushService.supported)
                    const PopupMenuItem(
                      value: 'push',
                      child: Text('Enable notifications'),
                    ),
                  const PopupMenuItem(value: 'logout', child: Text('Sign out')),
                ],
              ),
            ],
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => panel = 0),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chats'),
            ),
            TextButton.icon(
              onPressed: () => setState(() => panel = 1),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Contacts'),
            ),
            TextButton.icon(
              onPressed: () => setState(() => panel = 2),
              icon: const Icon(Icons.call),
              label: const Text('Calls'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search',
              isDense: true,
            ),
          ),
        ),
        if (panel == 0)
          Row(
            children: [
              const SizedBox(width: 16),
              ChoiceChip(
                label: const Text('All'),
                selected: !unread,
                onSelected: (_) => setState(() => unread = false),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Unread'),
                selected: unread,
                onSelected: (_) => setState(() => unread = true),
              ),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => run(chat.refresh),
            child: panel == 2
                ? ListView(
                    children: [
                      if (chat.calls.isEmpty)
                        const ListTile(title: Text('No calls yet')),
                      for (final c in chat.calls.where(
                        (c) => (c['peerUsername'] as String)
                            .toLowerCase()
                            .contains(query),
                      ))
                        ListTile(
                          leading: Icon(
                            c['outgoing'] == true
                                ? Icons.call_made
                                : Icons.call_received,
                          ),
                          title: Text(c['peerUsername'] as String),
                          subtitle: Text(
                            '${c['callType']} · ${c['status']}\n${localTime(c['startDate'])}${c['duration'] == null ? '' : ' · ${c['duration']} sec'}',
                          ),
                          trailing: const Icon(Icons.call_outlined),
                          onTap: () => run(
                            () => call.start(
                              c['peerUsername'] as String,
                              c['callType'] == 'Video',
                            ),
                          ),
                        ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: rows.isEmpty ? 1 : rows.length,
                    itemBuilder: (_, i) {
                      if (rows.isEmpty) {
                        return ListTile(
                          title: Text(
                            panel == 1
                                ? 'No contacts found'
                                : 'No conversations yet',
                          ),
                          subtitle: const Text(
                            'Start a conversation from Contacts.',
                          ),
                        );
                      }
                      final c = rows[i];
                      final label = panel == 1
                          ? (c['fullName'] as String? ??
                                c['username'] as String)
                          : name(c);
                      return ListTile(
                        selected: panel == 0 && c['id'] == chat.selected?['id'],
                        leading: avatar(label),
                        title: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          panel == 1
                              ? '${c['username']} · ${c['status']}'
                              : c['lastMessage'] as String? ??
                                    'Start the conversation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: panel == 0 && (c['unread'] as num) > 0
                            ? Badge(label: Text('${c['unread']}'))
                            : null,
                        onTap: () => run(() async {
                          if (recording) await cancelVoice();
                          composer.clear();
                          if (panel == 1) {
                            await chat.direct(c['username'] as String);
                          } else {
                            await chat.open(c);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ),
        ListTile(
          dense: true,
          leading: Icon(
            Icons.circle,
            size: 10,
            color: chat.connection == 'Connected'
                ? Colors.green
                : Colors.orange,
          ),
          title: Text(chat.connection),
          trailing: IconButton(
            tooltip: 'Reconnect and refresh',
            onPressed: () => run(chat.reconnect),
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }

  Widget conversation(bool wide) {
    final c = chat.selected;
    if (c == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 72, color: Color(0xff147d72)),
            SizedBox(height: 18),
            Text(
              'Your conversations, connected.',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(height: 8),
            Text('Choose a chat or start one from Contacts.'),
          ],
        ),
      );
    }
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: ListTile(
            leading: wide
                ? avatar(name(c))
                : IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => run(() async {
                      if (recording) await cancelVoice();
                      chat.closeConversation();
                    }),
                  ),
            title: Text(name(c)),
            subtitle: Text(c['peerStatus'] as String? ?? 'Offline'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Voice call',
                  onPressed: recording
                      ? null
                      : () => run(
                          () => call.start(c['peerUsername'] as String, false),
                        ),
                  icon: const Icon(Icons.call_outlined),
                ),
                IconButton(
                  tooltip: 'Video call',
                  onPressed: recording
                      ? null
                      : () => run(
                          () => call.start(c['peerUsername'] as String, true),
                        ),
                  icon: const Icon(Icons.videocam_outlined),
                ),
                IconButton(
                  tooltip: 'Leave conversation',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final leave = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Leave conversation?'),
                        content: const Text(
                          'This removes the conversation from your chat list.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Leave'),
                          ),
                        ],
                      ),
                    );
                    if (leave == true) {
                      await run(() async {
                        if (recording) await cancelVoice();
                        await chat.leave();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        if (chat.loading) const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(20),
            itemCount: chat.messages.length + 1,
            itemBuilder: (_, index) {
              if (index == chat.messages.length) {
                return chat.hasOlder && chat.messages.isNotEmpty
                    ? TextButton(
                        onPressed: chat.loading ? null : () => run(chat.older),
                        child: const Text('Load older messages'),
                      )
                    : const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Start of conversation',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
              }
              final m = chat.messages[chat.messages.length - 1 - index];
              return MessageBubble(
                key: ValueKey(m['id']),
                message: m,
                api: widget.api,
                onError: notice,
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Attach file',
                  onPressed: sending || recording ? null : () => run(attach),
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: recording
                      ? const Text('Recording voice note…')
                      : TextField(
                          controller: composer,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => send(),
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            isDense: true,
                          ),
                        ),
                ),
                if (recording)
                  IconButton(
                    tooltip: 'Cancel recording',
                    onPressed: () => run(cancelVoice),
                    icon: const Icon(Icons.delete_outline),
                  ),
                IconButton(
                  tooltip: recording ? 'Send voice note' : 'Record voice note',
                  onPressed: () => run(voice),
                  icon: Icon(
                    recording ? Icons.stop_circle : Icons.mic_none,
                    color: recording ? Colors.red : null,
                  ),
                ),
                if (!recording)
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: sending || chat.connection != 'Connected'
                        ? null
                        : send,
                    icon: const Icon(Icons.send),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget callOverlay() => Positioned.fill(
    child: Material(
      color: const Color(0xff102f2d),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              call.peer ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 30),
            ),
            Text(call.status, style: const TextStyle(color: Colors.white70)),
            Expanded(
              child: call.video && !call.incoming
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: RTCVideoView(
                            call.remote,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitContain,
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          width: 140,
                          height: 180,
                          child: RTCVideoView(call.local, mirror: true),
                        ),
                      ],
                    )
                  : const Icon(
                      Icons.account_circle,
                      size: 140,
                      color: Colors.white54,
                    ),
            ),
            Wrap(
              spacing: 20,
              children: [
                if (call.incoming)
                  FilledButton.icon(
                    onPressed: () => run(call.accept),
                    icon: const Icon(Icons.call),
                    label: const Text('Accept'),
                  ),
                if (!call.incoming) ...[
                  IconButton.filled(
                    tooltip: 'Mute microphone',
                    onPressed: call.mute,
                    icon: Icon(call.muted ? Icons.mic_off : Icons.mic),
                  ),
                  if (call.video)
                    IconButton.filled(
                      tooltip: 'Toggle camera',
                      onPressed: call.toggleCamera,
                      icon: Icon(
                        call.camera ? Icons.videocam : Icons.videocam_off,
                      ),
                    ),
                  if (!kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.android ||
                          defaultTargetPlatform == TargetPlatform.iOS))
                    IconButton.filled(
                      tooltip: 'Speaker',
                      onPressed: () => run(call.toggleSpeaker),
                      icon: Icon(
                        call.speaker ? Icons.volume_up : Icons.hearing,
                      ),
                    ),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => run(call.end),
                  icon: const Icon(Icons.call_end),
                  label: Text(call.incoming ? 'Decline' : 'End call'),
                ),
              ],
            ),
            const SizedBox(height: 36),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (_, bounds) {
          final wide = bounds.maxWidth >= 800;
          return Stack(
            children: [
              if (wide)
                Row(
                  children: [
                    SizedBox(width: 350, child: sidebar()),
                    const VerticalDivider(width: 1),
                    Expanded(child: conversation(true)),
                  ],
                )
              else if (chat.selected == null)
                sidebar()
              else
                conversation(false),
              if (call.peer != null) callOverlay(),
            ],
          );
        },
      ),
    ),
  );
}

String localTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class MessageBubble extends StatefulWidget {
  final Json message;
  final Api api;
  final void Function(String) onError;
  const MessageBubble({
    super.key,
    required this.message,
    required this.api,
    required this.onError,
  });
  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final player = AudioPlayer();
  StreamSubscription<PlayerState>? playback;
  Future<Uint8List>? preview;
  @override
  void initState() {
    super.initState();
    playback = player.playerStateStream.listen((state) {
      if (mounted) {
        setState(
          () => playing =
              state.playing &&
              state.processingState != ProcessingState.completed,
        );
      }
    });
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

  Uint8List? bytes;
  bool busy = false, playing = false;
  @override
  void dispose() {
    unawaited(playback?.cancel());
    unawaited(player.dispose());
    super.dispose();
  }

  Future<void> attachment(bool play) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final a = widget.message['attachment'] as Map;
      bytes ??= await widget.api.download(a['url'] as String);
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
    final m = widget.message,
        mine = m['mine'] == true,
        a = m['attachment'] as Map?;
    final audio = a != null && (a['mimeType'] as String).startsWith('audio/');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? const Color(0xffd6eee6) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preview != null)
              FutureBuilder<Uint8List>(
                future: preview,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Image unavailable. Use Download to retry.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      width: 180,
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      snapshot.data!,
                      width: 260,
                      height: 180,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, stack) =>
                          const Text('Cannot preview this image.'),
                    ),
                  );
                },
              ),
            if (m['text'] != null && (m['text'] as String).isNotEmpty)
              SelectableText(m['text'] as String),
            if (a != null)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (audio)
                    IconButton(
                      tooltip: playing ? 'Pause voice note' : 'Play voice note',
                      onPressed: busy ? null : () => attachment(true),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    ),
                  TextButton.icon(
                    onPressed: busy ? null : () => attachment(false),
                    icon: const Icon(Icons.download),
                    label: Text(busy ? 'Loading…' : a['fileName'] as String),
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Text(
              '${localTime(m['createdAt'])}${mine ? (m['read'] == true ? '  · Read' : '  · Sent') : ''}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
