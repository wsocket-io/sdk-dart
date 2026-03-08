/// wSocket Dart SDK — Realtime Pub/Sub client with Presence, History, and Push.
///
/// ```dart
/// import 'package:wsocket_io/wsocket_io.dart';
///
/// final client = WSocket('wss://your-server.com', 'your-api-key');
/// client.connect();
/// final ch = client.pubsub.channel('chat');
/// ch.subscribe((data, meta) => print(data));
/// ch.publish({'text': 'hello'});
/// ```
library wsocket_io;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

// ─── Types ──────────────────────────────────────────────────

class MessageMeta {
  final String id;
  final String channel;
  final int timestamp;
  MessageMeta({required this.id, required this.channel, required this.timestamp});
}

class PresenceMember {
  final String clientId;
  final Map<String, dynamic>? data;
  final int joinedAt;
  PresenceMember({required this.clientId, this.data, this.joinedAt = 0});
}

class HistoryMessage {
  final String id;
  final String channel;
  final dynamic data;
  final String publisherId;
  final int timestamp;
  final int sequence;
  HistoryMessage({
    required this.id,
    required this.channel,
    this.data,
    required this.publisherId,
    required this.timestamp,
    this.sequence = 0,
  });
}

class HistoryResult {
  final String channel;
  final List<HistoryMessage> messages;
  final bool hasMore;
  HistoryResult({required this.channel, required this.messages, this.hasMore = false});
}

class WSocketOptions {
  final bool autoReconnect;
  final int maxReconnectAttempts;
  final Duration reconnectDelay;
  final String? token;
  final bool recover;

  const WSocketOptions({
    this.autoReconnect = true,
    this.maxReconnectAttempts = 10,
    this.reconnectDelay = const Duration(seconds: 1),
    this.token,
    this.recover = true,
  });
}

// ─── Presence ───────────────────────────────────────────────

class Presence {
  final String _channelName;
  final void Function(Map<String, dynamic>) _send;

  final List<void Function(PresenceMember)> _enterCbs = [];
  final List<void Function(PresenceMember)> _leaveCbs = [];
  final List<void Function(PresenceMember)> _updateCbs = [];
  final List<void Function(List<PresenceMember>)> _membersCbs = [];

  Presence(this._channelName, this._send);

  Presence enter({Map<String, dynamic>? data}) {
    _send({'action': 'presence.enter', 'channel': _channelName, 'data': data});
    return this;
  }

  Presence leave() {
    _send({'action': 'presence.leave', 'channel': _channelName});
    return this;
  }

  Presence update(Map<String, dynamic> data) {
    _send({'action': 'presence.update', 'channel': _channelName, 'data': data});
    return this;
  }

  Presence get() {
    _send({'action': 'presence.get', 'channel': _channelName});
    return this;
  }

  Presence onEnter(void Function(PresenceMember) cb) { _enterCbs.add(cb); return this; }
  Presence onLeave(void Function(PresenceMember) cb) { _leaveCbs.add(cb); return this; }
  Presence onUpdate(void Function(PresenceMember) cb) { _updateCbs.add(cb); return this; }
  Presence onMembers(void Function(List<PresenceMember>) cb) { _membersCbs.add(cb); return this; }

  void handleEvent(String action, Map<String, dynamic> data) {
    switch (action) {
      case 'presence.enter':
        final m = _parseMember(data);
        for (final cb in _enterCbs) cb(m);
        break;
      case 'presence.leave':
        final m = _parseMember(data);
        for (final cb in _leaveCbs) cb(m);
        break;
      case 'presence.update':
        final m = _parseMember(data);
        for (final cb in _updateCbs) cb(m);
        break;
      case 'presence.members':
        final members = (data['members'] as List?)
            ?.map((e) => _parseMember(e as Map<String, dynamic>))
            .toList() ?? [];
        for (final cb in _membersCbs) cb(members);
        break;
    }
  }

  PresenceMember _parseMember(Map<String, dynamic> d) => PresenceMember(
    clientId: d['clientId'] as String? ?? '',
    data: d['data'] as Map<String, dynamic>?,
    joinedAt: (d['joinedAt'] as num?)?.toInt() ?? 0,
  );
}

// ─── Channel ────────────────────────────────────────────────

class Channel {
  final String name;
  final void Function(Map<String, dynamic>) _send;
  late final Presence presence;

  final List<void Function(dynamic, MessageMeta)> _messageCbs = [];
  final List<void Function(HistoryResult)> _historyCbs = [];

  Channel(this.name, this._send) {
    presence = Presence(name, _send);
  }

  Channel subscribe([void Function(dynamic, MessageMeta)? callback]) {
    if (callback != null) _messageCbs.add(callback);
    _send({'action': 'subscribe', 'channel': name});
    return this;
  }

  Channel unsubscribe() {
    _send({'action': 'unsubscribe', 'channel': name});
    _messageCbs.clear();
    return this;
  }

  Channel publish(dynamic data, {bool? persist}) {
    final msg = <String, dynamic>{
      'action': 'publish',
      'channel': name,
      'data': data,
      'id': _uuid(),
    };
    if (persist != null) msg['persist'] = persist;
    _send(msg);
    return this;
  }

  Channel history({int? limit, int? before, int? after, String? direction}) {
    final opts = <String, dynamic>{'action': 'history', 'channel': name};
    if (limit != null) opts['limit'] = limit;
    if (before != null) opts['before'] = before;
    if (after != null) opts['after'] = after;
    if (direction != null) opts['direction'] = direction;
    _send(opts);
    return this;
  }

  Channel onHistory(void Function(HistoryResult) cb) {
    _historyCbs.add(cb);
    return this;
  }

  void handleMessage(dynamic data, MessageMeta meta) {
    for (final cb in _messageCbs) cb(data, meta);
  }

  void handleHistory(HistoryResult result) {
    for (final cb in _historyCbs) cb(result);
  }

  static String _uuid() {
    final r = Random();
    return '${r.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}-'
        '${r.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')}-'
        '4${r.nextInt(1 << 12).toRadixString(16).padLeft(3, '0')}-'
        '${(r.nextInt(4) + 8).toRadixString(16)}${r.nextInt(1 << 12).toRadixString(16).padLeft(3, '0')}-'
        '${r.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}'
        '${r.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')}';
  }
}

// ─── PubSub Namespace ──────────────────────────────────────

class PubSubNamespace {
  final WSocket _client;
  PubSubNamespace(this._client);
  Channel channel(String name) => _client.channel(name);
}

// ─── Push Client ────────────────────────────────────────────

class PushClient {
  final String baseUrl;
  final String token;
  final String appId;

  PushClient({required this.baseUrl, required this.token, required this.appId});

  Future<void> registerFCM({required String deviceToken, required String memberId}) =>
      _post('register', {'memberId': memberId, 'platform': 'fcm', 'subscription': {'deviceToken': deviceToken}});

  Future<void> registerAPNs({required String deviceToken, required String memberId}) =>
      _post('register', {'memberId': memberId, 'platform': 'apns', 'subscription': {'deviceToken': deviceToken}});

  Future<void> sendToMember(String memberId, {required Map<String, dynamic> payload}) =>
      _post('send', {'memberId': memberId, 'payload': payload});

  Future<void> broadcast({required Map<String, dynamic> payload}) =>
      _post('broadcast', {'payload': payload});

  Future<void> unregister(String memberId, {String? platform}) async {
    final body = <String, dynamic>{'memberId': memberId};
    if (platform != null) body['platform'] = platform;
    await http.delete(
      Uri.parse('$baseUrl/api/push/unregister'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Future<bool> deleteSubscription(String subscriptionId) async {
    final resp = await http.delete(
      Uri.parse('$baseUrl/api/push/subscriptions/$subscriptionId'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId, 'Content-Type': 'application/json'},
    );
    return resp.statusCode == 200;
  }

  Future<Map<String, dynamic>> addChannel(String memberId, String channel) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/push/channels/add'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId, 'Content-Type': 'application/json'},
      body: jsonEncode({'memberId': memberId, 'channel': channel}),
    );
    return jsonDecode(resp.body);
  }

  Future<Map<String, dynamic>> removeChannel(String memberId, String channel) async {
    final resp = await http.post(
      Uri.parse('$baseUrl/api/push/channels/remove'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId, 'Content-Type': 'application/json'},
      body: jsonEncode({'memberId': memberId, 'channel': channel}),
    );
    return jsonDecode(resp.body);
  }

  Future<String?> getVapidKey() async {
    final qs = appId.isNotEmpty ? '?appId=$appId' : '';
    final resp = await http.get(
      Uri.parse('$baseUrl/api/push/vapid-key$qs'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId},
    );
    final data = jsonDecode(resp.body);
    return data['vapidPublicKey'] as String?;
  }

  Future<Map<String, dynamic>> listSubscriptions({String? memberId, String? platform, int? limit}) async {
    final params = <String>[];
    if (memberId != null) params.add('memberId=$memberId');
    if (platform != null) params.add('platform=$platform');
    if (limit != null) params.add('limit=$limit');
    final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
    final resp = await http.get(
      Uri.parse('$baseUrl/api/push/subscriptions$qs'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId},
    );
    return jsonDecode(resp.body);
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    await http.post(
      Uri.parse('$baseUrl/api/push/$path'),
      headers: {'Authorization': 'Bearer $token', 'X-App-Id': appId, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }
}

// ─── WSocket Client ────────────────────────────────────────

class WSocket {
  final String url;
  final String apiKey;
  final WSocketOptions options;

  WebSocketChannel? _channel;
  final Map<String, Channel> _channels = {};
  final Set<String> _subscribedChannels = {};
  int _lastMessageTs = 0;
  int _reconnectAttempts = 0;
  bool _connected = false;
  StreamSubscription? _subscription;

  final List<void Function()> _onConnectCbs = [];
  final List<void Function(int)> _onDisconnectCbs = [];
  final List<void Function(dynamic)> _onErrorCbs = [];

  late final PubSubNamespace pubsub = PubSubNamespace(this);

  WSocket(this.url, this.apiKey, [this.options = const WSocketOptions()]);

  bool get isConnected => _connected;

  WSocket onConnect(void Function() cb) { _onConnectCbs.add(cb); return this; }
  WSocket onDisconnect(void Function(int) cb) { _onDisconnectCbs.add(cb); return this; }
  WSocket onError(void Function(dynamic) cb) { _onErrorCbs.add(cb); return this; }

  WSocket connect() {
    var wsUrl = url;
    wsUrl += url.contains('?') ? '&' : '?';
    wsUrl += 'key=$apiKey';
    if (options.token != null) wsUrl += '&token=${options.token}';

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _channel!.ready.then((_) {
      _connected = true;
      _reconnectAttempts = 0;

      if (options.recover && _subscribedChannels.isNotEmpty && _lastMessageTs > 0) {
        final resumeData = jsonEncode({'channels': _subscribedChannels.toList(), 'since': _lastMessageTs});
        final token = base64UrlEncode(utf8.encode(resumeData));
        _send({'action': 'resume', 'token': token});
      } else {
        for (final ch in _subscribedChannels) {
          _send({'action': 'subscribe', 'channel': ch});
        }
      }
      for (final cb in _onConnectCbs) cb();
    }).catchError((e) {
      for (final cb in _onErrorCbs) cb(e);
      _maybeReconnect();
    });

    _subscription = _channel!.stream.listen(
      (data) => _handleMessage(data as String),
      onDone: () {
        _connected = false;
        for (final cb in _onDisconnectCbs) cb(_channel?.closeCode ?? 1000);
        _maybeReconnect();
      },
      onError: (e) {
        _connected = false;
        for (final cb in _onErrorCbs) cb(e);
        _maybeReconnect();
      },
    );

    return this;
  }

  void disconnect() {
    _connected = false;
    _subscription?.cancel();
    _channel?.sink.close(1000);
  }

  Channel channel(String name) => _channels.putIfAbsent(name, () => Channel(name, _send));

  PushClient configurePush({required String baseUrl, required String token, required String appId}) =>
      PushClient(baseUrl: baseUrl, token: token, appId: appId);

  void _send(Map<String, dynamic> msg) {
    if (!_connected) return;
    _channel?.sink.add(jsonEncode(msg));
  }

  void _handleMessage(String raw) {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      final action = msg['action'] as String?;
      if (action == null) return;
      final channelName = msg['channel'] as String?;

      switch (action) {
        case 'message':
          final ch = channelName != null ? _channels[channelName] : null;
          if (ch == null) return;
          final ts = (msg['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
          if (ts > _lastMessageTs) _lastMessageTs = ts;
          ch.handleMessage(msg['data'], MessageMeta(id: msg['id'] as String? ?? '', channel: channelName!, timestamp: ts));
          break;

        case 'subscribed':
          if (channelName != null) _subscribedChannels.add(channelName);
          break;

        case 'unsubscribed':
          if (channelName != null) _subscribedChannels.remove(channelName);
          break;

        case 'history':
          final ch = channelName != null ? _channels[channelName] : null;
          if (ch == null) return;
          final msgs = (msg['messages'] as List?)?.map((m) {
            final d = m as Map<String, dynamic>;
            return HistoryMessage(
              id: d['id'] as String? ?? '', channel: channelName!,
              data: d['data'], publisherId: d['publisherId'] as String? ?? '',
              timestamp: (d['timestamp'] as num?)?.toInt() ?? 0,
              sequence: (d['sequence'] as num?)?.toInt() ?? 0,
            );
          }).toList() ?? [];
          ch.handleHistory(HistoryResult(channel: channelName!, messages: msgs, hasMore: msg['hasMore'] == true));
          break;

        case 'presence.enter':
        case 'presence.leave':
        case 'presence.update':
        case 'presence.members':
          final ch = channelName != null ? _channels[channelName] : null;
          if (ch == null) return;
          ch.presence.handleEvent(action, msg);
          break;

        case 'error':
          final err = msg['error'] as String? ?? 'Unknown error';
          for (final cb in _onErrorCbs) cb(Exception(err));
          break;
      }
    } catch (e) {
      for (final cb in _onErrorCbs) cb(e);
    }
  }

  void _maybeReconnect() {
    if (!options.autoReconnect) return;
    if (_reconnectAttempts >= options.maxReconnectAttempts) return;
    _reconnectAttempts++;
    final delay = options.reconnectDelay * _reconnectAttempts;
    Future.delayed(delay, () {
      if (!_connected) connect();
    });
  }
}
