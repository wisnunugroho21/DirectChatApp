import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'api.dart';

class ChatStore extends ChangeNotifier {
  final Api api;
  late final HubConnection hub;
  List<Json> conversations = [], contacts = [], messages = [], calls = [];
  Json? selected;
  String connection = 'Connecting';
  String? error;
  bool loading = false, hasOlder = true;
  int _selectionVersion = 0;
  bool _closed = false;
  String? deviceToken;
  ChatStore(this.api) {
    hub = HubConnectionBuilder()
        .withUrl(
          '${Api.baseUrl}/chatHub',
          options: HttpConnectionOptions(
            accessTokenFactory: () async => api.token ?? '',
          ),
        )
        .withAutomaticReconnect()
        .build();
    hub.on('ConversationCreated', (_) => unawaited(guard(refresh)));
    hub.on('ReceiveMessage', (args) {
      if (args == null || args.isEmpty) return;
      final message = Map<String, dynamic>.from(args[0] as Map);
      if (message['conversationId'] == selected?['id']) {
        addMessage(message);
        unawaited(guard(markRead));
      }
      unawaited(guard(refresh));
    });
    hub.on('PresenceChanged', (args) {
      if (args == null || args.length < 2) return;
      for (final c in conversations) {
        if (c['peerUsername'] == args[0]) c['peerStatus'] = args[1];
      }
      for (final c in contacts) {
        if (c['username'] == args[0]) c['status'] = args[1];
      }
      if (selected?['peerUsername'] == args[0]) {
        selected!['peerStatus'] = args[1];
      }
      changed();
    });
    hub.on('MessagesRead', (args) {
      if (args?.first == selected?['peerUsername']) {
        for (final m in messages) {
          if (m['mine'] == true) m['read'] = true;
        }
        changed();
      }
    });
    hub.onreconnecting(({error}) {
      connection = 'Reconnecting';
      changed();
    });
    hub.onclose(({error}) {
      connection = 'Disconnected';
      changed();
    });
    hub.onreconnected(({connectionId}) {
      connection = 'Connected';
      changed();
      unawaited(
        guard(() async {
          if (deviceToken != null) {
            await hub.invoke('BindDevice', args: [deviceToken!]);
          }
          await refresh();
          if (selected != null) await open(selected!);
        }),
      );
    });
  }
  void changed() {
    if (!_closed) notifyListeners();
  }

  Future<void> guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      error = e.toString();
      changed();
    }
  }

  Future<void> start() async {
    await refresh();
    await hub.start();
    connection = 'Connected';
    changed();
  }

  Future<void> reconnect() async {
    if (hub.state == HubConnectionState.Disconnected) await hub.start();
    connection = hub.state == HubConnectionState.Connected
        ? 'Connected'
        : 'Connecting';
    await refresh();
    changed();
  }

  Future<void> refresh() async {
    final result = await Future.wait([
      api.request('GET', '/api/conversations'),
      api.request('GET', '/api/users'),
      api.request('GET', '/api/calls'),
    ]);
    conversations = (result[0] as List)
        .map((e) => Json.from(e as Map))
        .toList();
    contacts = (result[1] as List).map((e) => Json.from(e as Map)).toList();
    calls = (result[2] as List).map((e) => Json.from(e as Map)).toList();
    if (selected != null) {
      final current = conversations.where((c) => c['id'] == selected!['id']);
      if (current.isNotEmpty) selected = current.first;
    }
    changed();
  }

  Future<void> open(Json conversation) async {
    final version = ++_selectionVersion;
    selected = conversation;
    messages = [];
    hasOlder = true;
    loading = true;
    changed();
    try {
      final data = await api.request(
        'GET',
        '/api/conversations/${conversation['id']}/messages?limit=50',
      );
      if (version != _selectionVersion) return;
      // Keep messages received while history was loading.
      final merged = <String, Json>{};
      for (final m in [
        ...(data as List).map((e) => Json.from(e as Map)),
        ...messages,
      ]) {
        merged[m['id'] as String] = m;
      }
      messages = merged.values.toList()
        ..sort(
          (a, b) =>
              (a['createdAt'] as String).compareTo(b['createdAt'] as String),
        );
      hasOlder = data.length == 50;
      await markRead();
    } finally {
      if (version == _selectionVersion) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> older() async {
    if (selected == null || messages.isEmpty || loading || !hasOlder) return;
    final version = _selectionVersion;
    loading = true;
    changed();
    try {
      final before = Uri.encodeQueryComponent(
        messages.first['createdAt'] as String,
      );
      final data =
          await api.request(
                'GET',
                '/api/conversations/${selected!['id']}/messages?limit=50&before=$before',
              )
              as List;
      if (version != _selectionVersion) return;
      final ids = messages.map((m) => m['id']).toSet();
      messages.insertAll(
        0,
        data
            .map((e) => Json.from(e as Map))
            .where((m) => !ids.contains(m['id'])),
      );
      hasOlder = data.length == 50;
    } finally {
      if (version == _selectionVersion) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> direct(String username) async {
    final c = Json.from(
      await api.request(
            'POST',
            '/api/conversations/direct/${Uri.encodeComponent(username)}',
          )
          as Map,
    );
    await refresh();
    await open(c);
  }

  Future<void> createGroup(String name, List<String> usernames) async {
    final group = Json.from(
      await api.request('POST', '/api/conversations/groups', {
            'name': name.trim(),
            'usernames': usernames,
          })
          as Map,
    );
    await refresh();
    await open(group);
  }

  Future<void> openNotification({
    String? conversationId,
    String? sender,
  }) async {
    if (conversationId != null && conversationId.isNotEmpty) {
      await refresh();
      for (final c in conversations) {
        if (c['id'] == conversationId) {
          await open(c);
          return;
        }
      }
      throw StateError('This conversation is no longer available.');
    }
    if (sender != null && sender.isNotEmpty) await direct(sender);
  }

  Future<void> markAllRead() async {
    for (final c in conversations.where(
      (c) => (c['unread'] as num? ?? 0) > 0,
    )) {
      await api.request('POST', '/api/conversations/${c['id']}/read');
      c['unread'] = 0;
    }
    changed();
  }

  Future<void> markRead() async {
    final c = selected;
    if (c == null) return;
    if (c['type'] != 'Group' && hub.state == HubConnectionState.Connected) {
      await hub.invoke('MarkRead', args: [c['peerUsername'] as String]);
    } else {
      await api.request('POST', '/api/conversations/${c['id']}/read');
    }
    c['unread'] = 0;
    for (final row in conversations) {
      if (row['id'] == c['id']) row['unread'] = 0;
    }
    changed();
  }

  void addMessage(Json m) {
    if (selected?['id'] == m['conversationId'] &&
        !messages.any((x) => x['id'] == m['id'])) {
      messages.add(m);
      changed();
    }
  }

  Future<void> send(String text) async {
    if (selected == null || text.trim().isEmpty) return;
    final result = await hub.invoke(
      selected!['type'] == 'Group' ? 'SendConversationMessage' : 'SendMessage',
      args: [
        selected![selected!['type'] == 'Group' ? 'id' : 'peerUsername']
            as String,
        text.trim(),
      ],
    );
    addMessage(Json.from(result as Map));
    await refresh();
  }

  Future<void> leave() async {
    if (selected == null) return;
    await api.request('DELETE', '/api/conversations/${selected!['id']}');
    closeConversation();
    await refresh();
  }

  void closeConversation() {
    ++_selectionVersion;
    selected = null;
    messages = [];
    changed();
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(hub.stop());
    super.dispose();
  }
}
