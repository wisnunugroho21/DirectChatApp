import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:tms_connect/api.dart';

void main() {
  test(
    'API and SignalR preserve chat, attachment privacy, reads and video calls',
    () async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final clients = List.generate(3, (_) => Api());
      final names = ['alice$suffix', 'bob$suffix', 'eve$suffix'];
      final hubs = <HubConnection>[];
      addTearDown(() async {
        for (final h in hubs) {
          await h.stop();
        }
        for (final a in clients) {
          a.dispose();
        }
      });
      for (var i = 0; i < clients.length; i++) {
        await clients[i].request('POST', '/api/auth/register', {
          'username': names[i],
          'email': '${names[i]}@example.test',
          'fullName': names[i],
          'password': 'test-password-123',
          'confirmPassword': 'test-password-123',
        });
        final result = await clients[i].request('POST', '/api/auth/login', {
          'username': names[i],
          'password': 'test-password-123',
        });
        clients[i].token = result['accessToken'];
        expect(
          (await clients[i].request('GET', '/api/auth/me'))['username'],
          names[i],
        );
        final hub = HubConnectionBuilder()
            .withUrl(
              '${Api.baseUrl}/chatHub',
              options: HttpConnectionOptions(
                accessTokenFactory: () async => clients[i].token!,
              ),
            )
            .build();
        hubs.add(hub);
        await hub.start();
      }
      final conversation = await clients[0].request(
        'POST',
        '/api/conversations/direct/${names[1]}',
      );
      final incoming = Completer<Map>();
      hubs[1].on('ReceiveMessage', (args) {
        if (!incoming.isCompleted) incoming.complete(args!.first as Map);
      });
      final sent =
          await hubs[0].invoke('SendMessage', args: [names[1], 'Hello Flutter'])
              as Map;
      final received = await incoming.future.timeout(
        const Duration(seconds: 10),
      );
      expect(received['id'], sent['id']);
      expect(received['mine'], false);
      final history =
          await clients[1].request(
                'GET',
                "/api/conversations/${conversation['id']}/messages",
              )
              as List;
      expect(history.last['text'], 'Hello Flutter');
      await expectLater(
        clients[2].request(
          'GET',
          "/api/conversations/${conversation['id']}/messages",
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      final read = Completer<void>();
      hubs[0].on('MessagesRead', (_) {
        if (!read.isCompleted) read.complete();
      });
      await hubs[1].invoke('MarkRead', args: [names[0]]);
      await read.future.timeout(const Duration(seconds: 10));
      final attachment = await clients[0].upload(
        conversation['id'],
        Uint8List.fromList([104, 105]),
        'note.txt',
        'text/plain',
      );
      expect(await clients[1].download(attachment['attachment']['url']), [
        104,
        105,
      ]);
      await expectLater(
        clients[2].download(attachment['attachment']['url']),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      final ringing = Completer<List<Object?>>();
      hubs[1].on('IncomingCall', (args) {
        if (!ringing.isCompleted) ringing.complete(args!);
      });
      await hubs[0].invoke('CallUser', args: [names[1], 'Video']);
      expect(
        (await ringing.future.timeout(const Duration(seconds: 10)))[1],
        'Video',
      );
      await hubs[1].invoke('AcceptCall', args: [names[0]]);
      await hubs[0].invoke('EndCall', args: [names[1]]);
      final calls = await clients[0].request('GET', '/api/calls') as List;
      expect(calls.first['callType'], 'Video');
      expect(calls.first['status'], 'Completed');
      await clients[1].request(
        'DELETE',
        "/api/conversations/${conversation['id']}",
      );
      expect(await clients[1].request('GET', '/api/conversations'), isEmpty);
    },
    skip: !const bool.fromEnvironment('RUN_BACKEND_TESTS'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
