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
      final clients = List.generate(4, (_) => Api());
      final names = [
        'alice$suffix',
        'bob$suffix',
        'eve$suffix',
        'outsider$suffix',
      ];
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
      await expectLater(
        clients[0].request('POST', '/api/conversations/groups', {
          'name': 'Invalid',
          'usernames': [names[1]],
        }),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
      );
      final group = await clients[0].request(
        'POST',
        '/api/conversations/groups',
        {
          'name': 'Dispatch team',
          'usernames': [names[1], names[2]],
        },
      );
      expect(group['type'], 'Group');
      expect(group['memberCount'], 3);
      final groupMessage = Completer<Map>();
      hubs[2].on('ReceiveMessage', (args) {
        final m = args!.first as Map;
        if (m['conversationId'] == group['id'] && !groupMessage.isCompleted) {
          groupMessage.complete(m);
        }
      });
      await hubs[0].invoke(
        'SendConversationMessage',
        args: [group['id'], 'Group dispatch'],
      );
      expect(
        (await groupMessage.future.timeout(
          const Duration(seconds: 10),
        ))['text'],
        'Group dispatch',
      );
      await expectLater(
        hubs[3].invoke(
          'SendConversationMessage',
          args: [group['id'], 'Intrusion'],
        ),
        throwsA(anything),
      );
      final groupFile = await clients[1].upload(
        group['id'],
        Uint8List.fromList([42]),
        'group.txt',
        'text/plain',
      );
      expect(await clients[2].download(groupFile['attachment']['url']), [42]);
      await expectLater(
        clients[3].download(groupFile['attachment']['url']),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      final summaries =
          await clients[2].request('GET', '/api/conversations') as List;
      expect(summaries.single['memberCount'], 3);
      expect(summaries.single['unread'], 2);
      await clients[2].request(
        'POST',
        "/api/conversations/${group['id']}/read",
      );
      expect(
        (await clients[2].request('GET', '/api/conversations') as List)
            .single['unread'],
        0,
      );
      final groupRing = Completer<List<Object?>>();
      hubs[1].on('IncomingGroupCall', (args) {
        if (!groupRing.isCompleted) groupRing.complete(args!);
      });
      final room =
          await hubs[0].invoke('StartGroupCall', args: [group['id'], 'Video'])
              as Map;
      expect(
        (await groupRing.future.timeout(const Duration(seconds: 10)))[4],
        'Dispatch team',
      );
      expect(
        (await clients[1].request('GET', '/api/calls/ringing'))['groupCallId'],
        room['groupCallId'],
      );
      await expectLater(
        hubs[3].invoke('AcceptGroupCall', args: [room['groupCallId']]),
        throwsA(anything),
      );
      await hubs[1].invoke('AcceptGroupCall', args: [room['groupCallId']]);
      final offer = Completer<List<Object?>>();
      hubs[0].on('ReceiveGroupOffer', (args) {
        if (!offer.isCompleted) offer.complete(args!);
      });
      await hubs[1].invoke(
        'SendGroupOffer',
        args: [room['groupCallId'], names[0], '{"sdp":"test"}'],
      );
      expect(
        (await offer.future.timeout(const Duration(seconds: 10))).first,
        names[1],
      );
      await expectLater(
        hubs[1].invoke(
          'SendGroupOffer',
          args: [room['groupCallId'], names[3], '{}'],
        ),
        throwsA(anything),
      );
      await hubs[0].invoke('LeaveGroupCall', args: [room['groupCallId']]);
      expect(
        (await clients[1].request('GET', '/api/calls/ringing'))['ringing'],
        false,
      );
      final groupHistory =
          await clients[1].request('GET', '/api/calls') as List;
      expect(groupHistory.first['isGroup'], true);
      expect(groupHistory.first['status'], 'Completed');
      await clients[2].request('DELETE', "/api/conversations/${group['id']}");
      await expectLater(
        hubs[2].invoke(
          'SendConversationMessage',
          args: [group['id'], 'After leaving'],
        ),
        throwsA(anything),
      );
      expect(
        (await clients[0].request('GET', '/api/conversations') as List)
            .firstWhere((c) => c['id'] == group['id'])['memberCount'],
        2,
      );
    },
    skip: !const bool.fromEnvironment('RUN_BACKEND_TESTS'),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
