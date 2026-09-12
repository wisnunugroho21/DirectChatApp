import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tms_connect/api.dart';
import 'package:tms_connect/chat_store.dart';
import 'package:tms_connect/call_service.dart';

class TestApi extends Api {
  @override
  Future<dynamic> request(String method, String path, [Object? body]) async => {
    'iceServers': [],
  };
}

class TestChat extends ChatStore {
  TestChat(super.api);
  @override
  Future<void> refresh() async {}
}

class TestRenderer implements RTCVideoRenderer {
  @override
  MediaStream? srcObject;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestTrack implements MediaStreamTrack {
  int stops = 0;
  bool fail = false;
  Completer<void>? releasing;
  @override
  Future<void> stop() async {
    stops++;
    if (releasing != null) await releasing!.future;
    if (fail) throw StateError('Track stop failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestStream implements MediaStream {
  final List<TestTrack> tracks;
  bool disposed = false;
  TestStream(this.tracks);
  @override
  List<MediaStreamTrack> getTracks() => tracks;
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late TestApi api;
  late TestChat chat;
  late CallService call;
  setUp(() {
    api = TestApi();
    chat = TestChat(api);
  });
  tearDown(() async {
    await call.end(notifyPeer: false);
    call.dispose();
    chat.dispose();
    api.dispose();
  });
  CallService make(
    Future<MediaStream> Function(Map<String, dynamic>) acquire, {
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? createPeer,
  }) {
    return CallService(
      chat,
      getUserMedia: acquire,
      createPeer: createPeer,
      localRenderer: TestRenderer(),
      remoteRenderer: TestRenderer(),
    );
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('concurrent media requests acquire only one stream', () async {
    final pending = Completer<MediaStream>();
    var requests = 0;
    final track = TestTrack();
    final stream = TestStream([track]);
    call = make((_) {
      requests++;
      return pending.future;
    });
    call.peer = 'peer';
    call.group = true;
    call.video = true;
    final first = call.media();
    final second = call.media();
    await flush();
    expect(requests, 1);
    pending.complete(stream);
    await Future.wait([first, second]);
    await call.media();
    expect(requests, 1);
    await call.end(notifyPeer: false);
    expect(track.stops, 1);
    expect(stream.disposed, isTrue);
  });

  test('accepting twice cannot acquire the camera twice', () async {
    final pending = Completer<MediaStream>();
    var requests = 0;
    final stream = TestStream([TestTrack()]);
    call = make((_) {
      requests++;
      return pending.future;
    });
    call.peer = 'peer';
    call.incoming = true;
    call.video = true;
    final accepted = call.accept();
    await flush();
    expect(call.accepting, isTrue);
    await call.accept();
    expect(requests, 1);
    final ending = call.end(notifyPeer: false);
    pending.complete(stream);
    await Future.wait([accepted, ending]);
    expect(stream.disposed, isTrue);
    expect(call.peer, isNull);
  });

  test(
    'cancelled camera request releases its late stream without calling the peer',
    () async {
      final pending = Completer<MediaStream>();
      final track = TestTrack();
      final stream = TestStream([track]);
      call = make((_) => pending.future);
      final starting = call.start('peer', true);
      await flush();
      final ending = call.end(notifyPeer: false);
      expect(call.peer, isNull);
      expect(call.closing, isTrue);
      pending.complete(stream);
      await Future.wait([starting, ending]);
      expect(track.stops, 1);
      expect(stream.disposed, isTrue);
      expect(call.error, isNull);
    },
  );

  test('next call waits for previous tracks to finish releasing', () async {
    final release = Completer<void>();
    final firstTrack = TestTrack()..releasing = release;
    final secondCapture = Completer<MediaStream>();
    var requests = 0;
    call = make((_) async {
      requests++;
      return requests == 1 ? TestStream([firstTrack]) : secondCapture.future;
    });
    call.peer = 'first';
    call.group = true;
    await call.media();
    final ending = call.end(notifyPeer: false);
    final next = call.start('second', true);
    await flush();
    expect(requests, 1);
    release.complete();
    await ending;
    await flush();
    expect(requests, 2);
    final endNext = call.end(notifyPeer: false);
    final stream = TestStream([TestTrack()]);
    secondCapture.complete(stream);
    await Future.wait([next, endNext]);
    expect(stream.disposed, isTrue);
  });

  test('peer setup failure still releases captured devices', () async {
    final track = TestTrack();
    final stream = TestStream([track]);
    call = make(
      (_) async => stream,
      createPeer: (_) async => throw StateError('Peer setup failed'),
    );
    await expectLater(call.start('peer', true), throwsStateError);
    expect(track.stops, 1);
    expect(stream.disposed, isTrue);
  });

  test(
    'one failing track does not prevent the others from being released',
    () async {
      final broken = TestTrack()..fail = true;
      final camera = TestTrack();
      final stream = TestStream([broken, camera]);
      call = make((_) async => stream);
      call.peer = 'peer';
      call.group = true;
      await call.media();
      await call.end(notifyPeer: false);
      expect(camera.stops, 1);
      expect(stream.disposed, isTrue);
    },
  );

  test('busy hardware error gives actionable guidance', () async {
    call = make(
      (_) async => throw StateError(
        'unable to getUserMedia: NotReadableError: device in use',
      ),
    );
    await expectLater(
      call.start('peer', true),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Close other camera apps or call tabs'),
        ),
      ),
    );
    expect(call.peer, isNull);
    expect(
      CallService.mediaError(StateError('NotAllowedError')),
      contains('Allow access'),
    );
  });
}
