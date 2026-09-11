import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api.dart';
import 'chat_store.dart';

class GroupPeer {
  final RTCPeerConnection connection;
  final RTCVideoRenderer renderer;
  final pending = <RTCIceCandidate>[];
  bool ready = false, camera = true;
  GroupPeer(this.connection, this.renderer);
}

class CallService extends ChangeNotifier {
  final ChatStore chat;
  final local = RTCVideoRenderer(), remote = RTCVideoRenderer();
  String? groupId, groupName, groupConversationId;
  bool group = false;
  final participants = <String, GroupPeer>{};
  Json? _config;
  String get displayName => group ? groupName ?? 'Group call' : peer ?? '';
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

    on('IncomingGroupCall', (a) async {
      if (peer != null) {
        await chat.hub.invoke('RejectGroupCall', args: [a[2] as String]);
        return;
      }
      group = true;
      peer = a[0] as String;
      groupId = a[2] as String;
      groupConversationId = a[3] as String;
      groupName = a[4] as String;
      video = a[5] == 'Video';
      incoming = true;
      status = 'Incoming group call';
      changed();
      ringTimeout();
    });
    on('GroupCallReady', (a) async {
      if (!group || peer == null) {
        await chat.hub.invoke('LeaveGroupCall', args: [a[0] as String]);
        return;
      }
      groupId = a[0] as String;
      status = 'Waiting for members…';
      changed();
    });
    on('GroupCallHandled', (a) async {
      if (groupId == a[0] && a[1] != chat.hub.connectionId) {
        await end(notifyPeer: false);
      }
    });
    on('GroupCallAccepted', (a) async {
      if (!group || groupId != a[0] || peer == null) return;
      incoming = false;
      status = 'Connecting to group…';
      changed();
      for (final username in a[1] as List) {
        final entry = await groupPeer(username as String);
        final offer = await entry.connection.createOffer();
        await entry.connection.setLocalDescription(offer);
        await chat.hub.invoke(
          'SendGroupOffer',
          args: [groupId!, username, jsonEncode(offer.toMap())],
        );
      }
    });
    on('ReceiveGroupOffer', (a) async {
      if (!group || groupId != a[1] || incoming) return;
      final entry = await groupPeer(a[0] as String);
      final data = jsonDecode(a[2] as String) as Map;
      await entry.connection.setRemoteDescription(
        RTCSessionDescription(data['sdp'], data['type']),
      );
      await drainGroupIce(entry);
      final answer = await entry.connection.createAnswer();
      await entry.connection.setLocalDescription(answer);
      await chat.hub.invoke(
        'SendGroupAnswer',
        args: [groupId!, a[0] as String, jsonEncode(answer.toMap())],
      );
    });
    on('ReceiveGroupAnswer', (a) async {
      if (!group || groupId != a[1]) return;
      final entry = participants[a[0]];
      if (entry == null) return;
      final data = jsonDecode(a[2] as String) as Map;
      await entry.connection.setRemoteDescription(
        RTCSessionDescription(data['sdp'], data['type']),
      );
      await drainGroupIce(entry);
    });
    on('ReceiveGroupIceCandidate', (a) async {
      if (!group || groupId != a[1] || incoming) return;
      final entry = await groupPeer(a[0] as String);
      final data = jsonDecode(a[2] as String) as Map;
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      if (entry.ready) {
        await entry.connection.addCandidate(candidate);
      } else {
        entry.pending.add(candidate);
      }
    });
    on('GroupParticipantLeft', (a) async {
      if (groupId != a[0]) return;
      await removeGroupPeer(a[1] as String);
    });
    on('GroupParticipantDeclined', (a) async {
      if (groupId == a[0]) {
        status = '${a[1]} declined the group call';
        changed();
      }
    });
    on('GroupCameraStateChanged', (a) async {
      if (groupId == a[0]) {
        participants[a[1]]?.camera = a[2] == true;
        changed();
      }
    });
    on('GroupCallEnded', (a) async {
      if (groupId == a[0]) await end(notifyPeer: false);
    });
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

  Future<void> drainGroupIce(GroupPeer entry) async {
    entry.ready = true;
    for (final candidate in entry.pending) {
      await entry.connection.addCandidate(candidate);
    }
    entry.pending.clear();
  }

  Future<GroupPeer> groupPeer(String username) async {
    if (participants[username] != null) return participants[username]!;
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    final pc = await createPeerConnection(_config!);
    final entry = GroupPeer(pc, renderer);
    participants[username] = entry;
    for (final track in _stream!.getTracks()) {
      await pc.addTrack(track, _stream!);
    }
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
        changed();
      }
    };
    pc.onIceCandidate = (candidate) {
      if (groupId != null && candidate.candidate != null) {
        unawaited(
          chat.guard(() async {
            await chat.hub.invoke(
              'SendGroupIceCandidate',
              args: [groupId!, username, jsonEncode(candidate.toMap())],
            );
          }),
        );
      }
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _timeout?.cancel();
        status = '${participants.length + 1} participants connected';
        changed();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(removeGroupPeer(username));
      }
    };
    changed();
    return entry;
  }

  Future<void> removeGroupPeer(String username) async {
    final entry = participants.remove(username);
    if (entry == null) return;
    await entry.connection.close();
    entry.renderer.srcObject = null;
    await entry.renderer.dispose();
    changed();
  }

  Future<void> startConversation(Json conversation, bool withVideo) async {
    if (conversation['type'] != 'Group') {
      await start(conversation['peerUsername'] as String, withVideo);
      return;
    }
    if (peer != null) return;
    if ((conversation['memberCount'] as num? ?? 0) > 8) {
      throw StateError('Group calls support up to 8 participants.');
    }
    group = true;
    groupName =
        conversation['name'] as String? ??
        conversation['peerFullName'] as String?;
    groupConversationId = conversation['id'] as String;
    peer = groupConversationId;
    video = withVideo;
    camera = withVideo;
    incoming = false;
    status = 'Calling group members…';
    changed();
    try {
      await media();
      if (peer == null) return;
      final result = Json.from(
        await chat.hub.invoke(
              'StartGroupCall',
              args: [groupConversationId!, video ? 'Video' : 'Audio'],
            )
            as Map,
      );
      if (!group || peer == null) {
        await chat.hub.invoke(
          'LeaveGroupCall',
          args: [result['groupCallId'] as String],
        );
        return;
      }
      groupId = result['groupCallId'] as String;
      ringTimeout();
    } catch (e) {
      error = e.toString();
      await end();
      rethrow;
    }
  }

  Future<void> media() async {
    final config = Json.from(
      await chat.api.request('GET', '/api/webrtc/config') as Map,
    );
    _config = config;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video,
    });
    if (peer == null || _disposed) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    _stream = stream;
    local.srcObject = _stream;
    if (group) return;
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
      if (peer == null) return;
      await chat.hub.invoke(
        group ? 'AcceptGroupCall' : 'AcceptCall',
        args: [group ? groupId! : peer!],
      );
      ringTimeout();
    } catch (e) {
      error = e.toString();
      await end();
      rethrow;
    }
  }

  Future<void> end({bool notifyPeer = true}) async {
    final target = peer;
    final room = groupId;
    final wasGroup = group;
    groupId = null;
    group = false;
    groupName = null;
    groupConversationId = null;
    for (final username in participants.keys.toList()) {
      await removeGroupPeer(username);
    }
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
    if (notifyPeer && target != null && (!wasGroup || room != null)) {
      await chat.guard(() async {
        await chat.hub.invoke(
          wasGroup
              ? (wasIncoming ? 'RejectGroupCall' : 'LeaveGroupCall')
              : (wasIncoming ? 'RejectCall' : 'EndCall'),
          args: [wasGroup ? room! : target],
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
    if (groupId != null) {
      unawaited(
        chat.guard(() async {
          await chat.hub.invoke(
            'SendGroupCameraState',
            args: [groupId!, camera],
          );
        }),
      );
    }
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
