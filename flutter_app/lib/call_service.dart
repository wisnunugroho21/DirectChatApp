import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api.dart';
import 'chat_store.dart';

class CallService extends ChangeNotifier {
  final ChatStore chat;
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  final List<RTCIceCandidate> _pending = [];
  String? peer, error;
  String status = '';
  bool incoming = false,
      video = false,
      muted = false,
      camera = true,
      speaker = false;
  bool _remoteReady = false, _disposed = false;
  Timer? _timeout;
  Future<void> _queue = Future.value();
  CallService(this.chat);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    await local.initialize();
    await remote.initialize();
    void on(String event, Future<void> Function(List<Object?>) action) {
      chat.hub.on(event, (args) {
        if (args == null) return;
        _queue = _queue.then((_) => action(args)).catchError((Object e) async {
          error = e.toString();
          await end();
        });
      });
    }

    on('IncomingCall', (a) async {
      if (peer != null) {
        await chat.hub.invoke('RejectCall', args: [a[0] as String]);
        return;
      }
      peer = a[0] as String;
      incoming = true;
      video = a.length > 1 && a[1] == 'Video';
      status = 'Incoming call';
      changed();
      ringTimeout();
    });
    on('CallAccepted', (a) async {
      if (a[0] != peer || incoming || _pc == null) return;
      _timeout?.cancel();
      status = 'Connecting';
      changed();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      await chat.hub.invoke(
        'SendOffer',
        args: [peer!, jsonEncode(offer.toMap())],
      );
    });
    on('ReceiveOffer', (a) async {
      if (a[0] != peer || _pc == null || incoming) return;
      final offer = jsonDecode(a[1] as String) as Map;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      await drainIce();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await chat.hub.invoke(
        'SendAnswer',
        args: [peer!, jsonEncode(answer.toMap())],
      );
    });
    on('ReceiveAnswer', (a) async {
      if (a[0] != peer || _pc == null) return;
      final answer = jsonDecode(a[1] as String) as Map;
      await _pc!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
      await drainIce();
    });
    on('ReceiveIceCandidate', (a) async {
      if (peer == null) return;
      // New backend includes sender identity; ignore candidates from other callers.
      if (a.length > 1 && a[1] != peer) return;
      final c = jsonDecode(a[0] as String) as Map;
      final candidate = RTCIceCandidate(
        c['candidate'],
        c['sdpMid'],
        c['sdpMLineIndex'],
      );
      if (!_remoteReady) {
        _pending.add(candidate);
      } else {
        await _pc?.addCandidate(candidate);
      }
    });
    for (final event in ['CallRejected', 'CallEnded']) {
      on(event, (a) async {
        if (a[0] == peer) await end(notifyPeer: false);
      });
    }
  }

  void ringTimeout() {
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 45), () {
      unawaited(end());
    });
  }

  Future<void> drainIce() async {
    _remoteReady = true;
    for (final c in _pending) {
      await _pc!.addCandidate(c);
    }
    _pending.clear();
  }

  Future<void> media() async {
    final config = Json.from(
      await chat.api.request('GET', '/api/webrtc/config') as Map,
    );
    _stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
    local.srcObject = _stream;
    _pc = await createPeerConnection(config);
    for (final track in _stream!.getTracks()) {
      await _pc!.addTrack(track, _stream!);
    }
    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remote.srcObject = event.streams.first;
        changed();
      }
    };
    _pc!.onIceCandidate = (candidate) {
      if (peer != null && candidate.candidate != null) {
        unawaited(
          chat.guard(() async {
            await chat.hub.invoke(
              'SendIceCandidate',
              args: [peer!, jsonEncode(candidate.toMap())],
            );
          }),
        );
      }
    };
    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _timeout?.cancel();
        status = 'Connected';
        changed();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        error = 'Call connection failed. Check the server TURN configuration.';
        unawaited(end());
      }
    };
  }

  Future<void> start(String username, bool withVideo) async {
    if (peer != null) return;
    peer = username;
    video = withVideo;
    camera = withVideo;
    status = 'Calling';
    incoming = false;
    changed();
    try {
      await media();
      await chat.hub.invoke(
        'CallUser',
        args: [username, withVideo ? 'Video' : 'Audio'],
      );
      ringTimeout();
    } catch (e) {
      error = e.toString();
      await end();
      rethrow;
    }
  }

  Future<void> accept() async {
    if (!incoming || peer == null) return;
    _timeout?.cancel();
    status = 'Connecting';
    changed();
    try {
      await media();
      incoming = false;
      await chat.hub.invoke('AcceptCall', args: [peer!]);
      ringTimeout();
    } catch (e) {
      error = e.toString();
      await end();
      rethrow;
    }
  }

  Future<void> end({bool notifyPeer = true}) async {
    final target = peer;
    final wasIncoming = incoming;
    peer = null;
    incoming = false;
    _timeout?.cancel();
    final pc = _pc;
    _pc = null;
    await pc?.close();
    for (final track in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _stream?.dispose();
    _stream = null;
    local.srcObject = null;
    remote.srcObject = null;
    _pending.clear();
    _remoteReady = false;
    muted = false;
    speaker = false;
    changed();
    if (notifyPeer && target != null) {
      await chat.guard(() async {
        await chat.hub.invoke(
          wasIncoming ? 'RejectCall' : 'EndCall',
          args: [target],
        );
      });
    }
    if (target != null) await chat.guard(chat.refresh);
  }

  void mute() {
    muted = !muted;
    for (final t in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    changed();
  }

  void toggleCamera() {
    camera = !camera;
    for (final t in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camera;
    }
    changed();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    unawaited(
      end(notifyPeer: false).then((_) async {
        await local.dispose();
        await remote.dispose();
      }),
    );
    super.dispose();
  }
}
