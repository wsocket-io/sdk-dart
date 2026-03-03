# wSocket SDK for Dart / Flutter

Official Dart SDK for wSocket — realtime pub/sub, presence, history, and push notifications for Dart and Flutter apps.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  wsocket_io: ^0.1.0
```

Then run:

```bash
dart pub get
# or for Flutter
flutter pub get
```

## Quick Start

```dart
import 'package:wsocket_io/wsocket_io.dart';

final client = WSocket('wss://node00.wsocket.online', 'your-api-key');

client.onConnect(() {
  print('Connected!');
});

client.connect();

final channel = client.pubsub.channel('chat');

channel.subscribe((data, meta) {
  print('Received: $data');
});

channel.publish({'text': 'Hello from Dart!'});
```

## Presence

```dart
final channel = client.pubsub.channel('room');

channel.presence.enter(data: {'name': 'Alice'});

channel.presence.onEnter((member) {
  print('${member.clientId} entered');
});

channel.presence.onLeave((member) {
  print('${member.clientId} left');
});

channel.presence.get();
channel.presence.onMembers((members) {
  print('Online: ${members.length}');
});
```

## History

```dart
channel.history(limit: 50);
channel.onHistory((result) {
  for (final msg in result.messages) {
    print('${msg.publisherId}: ${msg.data}');
  }
});
```

## Push Notifications

```dart
final push = PushClient(
  baseUrl: 'https://node00.wsocket.online',
  token: 'secret',
  appId: 'app1',
);

// Register FCM device
push.registerFCM(deviceToken: fcmToken, memberId: 'user-123');

// Send to a member
push.sendToMember('user-123', payload: {
  'title': 'New message',
  'body': 'You have a new message',
});

// Broadcast
push.broadcast(payload: {'title': 'Announcement', 'body': 'Server update'});
```

## Requirements

- Dart 3.0+ / Flutter 3.10+

## License

MIT
