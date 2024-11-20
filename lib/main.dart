import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audio_service/audio_service.dart';

late MyAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.rebelonion.musiccontroller.channel.audio',
      androidNotificationChannelName: 'Music Controller',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const MusicControllerApp());
}

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  WebSocketChannel? _channel;

  void updateChannel(WebSocketChannel channel) {
    _channel = channel;
  }

  @override
  Future<void> play() async {
    _channel?.sink.add(jsonEncode({
      'type': 'PlaybackCommand',
      'action': 'PLAY',
    }));
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    _channel?.sink.add(jsonEncode({
      'type': 'PlaybackCommand',
      'action': 'PAUSE',
    }));
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> seek(Duration position) async {
    _channel?.sink.add(jsonEncode({
      'type': 'SeekCommand',
      'position': position.inMilliseconds.toDouble(),
    }));
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
      queueIndex: playbackState.value.queueIndex,
    ));
  }

  @override
  Future<void> skipToNext() async {
    _channel?.sink.add(jsonEncode({
      'type': 'PlaybackCommand',
      'action': 'NEXT',
    }));
  }

  @override
  Future<void> skipToPrevious() async {
    _channel?.sink.add(jsonEncode({
      'type': 'PlaybackCommand',
      'action': 'PREVIOUS',
    }));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _channel?.sink.add(jsonEncode({
      'type': 'ShuffleCommand',
      'enabled': shuffleMode == AudioServiceShuffleMode.all,
    }));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final mode = switch (repeatMode) {
      AudioServiceRepeatMode.none => 'OFF',
      AudioServiceRepeatMode.all => 'ALL',
      AudioServiceRepeatMode.one => 'ONE',
      AudioServiceRepeatMode.group => 'OFF',
    };
    _channel?.sink.add(jsonEncode({
      'type': 'RepeatCommand',
      'mode': mode,
    }));
  }

  void updatePlaybackState({
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    required String repeatMode,
    required bool shuffle,
  }) {
    final repeat = switch (repeatMode) {
      'OFF' => AudioServiceRepeatMode.none,
      'ALL' => AudioServiceRepeatMode.all,
      'ONE' => AudioServiceRepeatMode.one,
      String() => AudioServiceRepeatMode.none,
    };

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
      },
      androidCompactActionIndices: const [0, 1, 2],
      playing: isPlaying,
      updatePosition: position,
      processingState: AudioProcessingState.ready,
      repeatMode: repeat,
      shuffleMode: shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }

  void updateNowPlaying({
    required String title,
    required String artist,
    required String album,
    required Duration duration,
    String? artworkUrl,
  }) {
    mediaItem.add(MediaItem(
      id: title,
      album: album,
      title: title,
      artist: artist,
      duration: duration,
      artUri: artworkUrl != null && artworkUrl.isNotEmpty
          ? Uri.parse(artworkUrl)
          : null,
    ));
  }
}

class MusicControllerApp extends StatelessWidget {
  const MusicControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Controller',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const ConnectPage(),
    );
  }
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _keyController = TextEditingController();
  bool _isConnecting = false;
  String? _error;

  void _connect() {
    if (_keyController.text.isEmpty) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final wsUrl = 'ws://localhost:8080/ws';
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    // Send connect message
    channel.sink.add(jsonEncode({
      'type': 'ControllerConnect',
      'key': _keyController.text,
    }));

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ControllerPage(
          channel: channel,
          connectionKey: _keyController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Enter Controller Key',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _keyController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Key',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _isConnecting ? null : _connect,
                  child: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ControllerPage extends StatefulWidget {
  final WebSocketChannel channel;
  final String connectionKey;

  const ControllerPage({
    super.key,
    required this.channel,
    required this.connectionKey,
  });

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> with SingleTickerProviderStateMixin {
  late final AnimationController _positionController;
  DateTime? _lastPositionUpdate;
  String _currentTrack = 'No track playing';
  String _artist = '';
  String _album = '';
  String _playbackState = 'PAUSED';
  List<dynamic> _playlist = [];
  int _currentIndex = 0;
  double _position = 0;
  double _duration = 1;
  double _volume = 1.0;
  bool _shuffle = false;
  String _repeatMode = 'OFF';
  String? _artworkUrl;
  bool _isDraggingSeek = false;
  double _dragPosition = 0;

  @override
  void initState() {
    super.initState();

    audioHandler.updateChannel(widget.channel);

    _positionController = AnimationController(
      vsync: this,
      value: 0,
      duration: const Duration(hours: 1),
    );

    _positionController.addListener(() {
      if (!_isDraggingSeek && _playbackState == 'PLAYING') {
        setState(() {
          final now = DateTime.now();
          final timeSinceLastUpdate = _lastPositionUpdate != null
              ? now.difference(_lastPositionUpdate!).inMilliseconds / 1000
              : 0.0;
          _position = _position + timeSinceLastUpdate;
          _lastPositionUpdate = now;
          _position = _position.clamp(0, _duration);
        });
      }
    });

    widget.channel.stream.listen(
          (message) {
        final data = jsonDecode(message);
        switch (data['type']) {
          case 'PlaybackStateUpdate':
            setState(() {
              _playbackState = data['state'];
              _currentTrack = data['track']['title'];
              _artist = data['track']['artist'];
              _album = data['track']['album'];
              _artworkUrl = data['track']['artworkUrl'];
              if (!_isDraggingSeek) {
                _position = data['currentPosition'] / 1000;
                _lastPositionUpdate = DateTime.now();
                if (_playbackState == 'PLAYING') {
                  _positionController.repeat();
                } else {
                  _positionController.stop();
                }
              }
              _duration = data['track']['duration'] / 1000;

              // Update audio service
              audioHandler.updatePlaybackState(
                isPlaying: _playbackState == 'PLAYING',
                position: Duration(milliseconds: data['currentPosition'].round()),
                duration: Duration(milliseconds: data['track']['duration'].round()),
                repeatMode: _repeatMode,
                shuffle: _shuffle,
              );
              audioHandler.updateNowPlaying(
                title: _currentTrack,
                artist: _artist,
                album: _album,
                duration: Duration(milliseconds: data['track']['duration'].round()),
                artworkUrl: _artworkUrl,
              );
            });
            break;
          case 'PlaylistUpdate':
            setState(() {
              _playlist = data['tracks'];
              _currentIndex = data['currentIndex'];
            });
            break;
          case 'PlaybackModeUpdate':
            setState(() {
              _shuffle = data['shuffle'];
              _repeatMode = data['repeatMode'];
            });
            break;
          case 'VolumeUpdate':
            setState(() {
              _volume = data['volume'];
            });
            break;
        }
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection lost. Please reconnect.'),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const ConnectPage(),
          ),
        );
      },
    );

    _sendCommand('RequestCurrentState');
  }

  void _sendCommand(String type, {Map<String, dynamic>? extra}) {
    final message = {'type': type, ...?extra};
    widget.channel.sink.add(jsonEncode(message));
  }

  void _handleSeekChange(double value) {
    setState(() {
      _isDraggingSeek = true;
      _dragPosition = value.clamp(0, _duration);
      if (_dragPosition > _duration) _dragPosition = _duration;
    });
  }

  void _handleSeekEnd(double value) {
    final clampedValue = value.clamp(0.0, _duration.toDouble());
    setState(() {
      _isDraggingSeek = false;
      _position = clampedValue;
      if (_position > _duration) _position = _duration;
    });
    _sendCommand('SeekCommand', extra: {'position': clampedValue * 1000});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Controller'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () {
            widget.channel.sink.close();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const ConnectPage(),
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              _shuffle ? Icons.shuffle : Icons.shuffle_outlined,
              color: _shuffle ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () {
              _sendCommand('ShuffleCommand', extra: {'enabled': !_shuffle});
            },
          ),
          IconButton(
            icon: Icon(
              _repeatMode == 'ONE'
                  ? Icons.repeat_one
                  : _repeatMode == 'ALL'
                  ? Icons.repeat
                  : Icons.repeat_outlined,
              color: _repeatMode != 'OFF'
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () {
              final nextMode = switch (_repeatMode) {
                'OFF' => 'ALL',
                'ALL' => 'ONE',
                'ONE' => 'OFF',
                String() => 'OFF',
              };
              _sendCommand('RepeatCommand', extra: {'mode': nextMode});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Now Playing Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_artworkUrl != null && _artworkUrl!.isNotEmpty)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _artworkUrl!,
                          height: 200,
                          width: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _currentTrack,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    _artist,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_album.isNotEmpty)
                    Text(
                      _album,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(Duration(seconds: _position.round())
                          .toString()
                          .split('.')
                          .first
                          .padLeft(8, "0")),
                      Expanded(
                        child: Slider(
                          value: _isDraggingSeek ? _dragPosition : _position,
                          max: _duration,
                          onChanged: _handleSeekChange,
                          onChangeEnd: _handleSeekEnd,
                        ),
                      ),
                      Text(Duration(seconds: _duration.round())
                          .toString()
                          .split('.')
                          .first
                          .padLeft(8, "0")),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.volume_down),
                      Expanded(
                        child: Slider(
                          value: _volume,
                          onChanged: (value) {
                            setState(() => _volume = value);
                            _sendCommand(
                              'VolumeCommand',
                              extra: {'volume': value},
                            );
                          },
                        ),
                      ),
                      const Icon(Icons.volume_up),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => _sendCommand(
                          'PlaybackCommand',
                          extra: {'action': 'PREVIOUS'},
                        ),
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        onPressed: () => _sendCommand(
                          'PlaybackCommand',
                          extra: {
                            'action':
                            _playbackState == 'PLAYING' ? 'PAUSE' : 'PLAY'
                          },
                        ),
                        icon: Icon(
                          _playbackState == 'PLAYING'
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                        ),
                        iconSize: 48,
                      ),
                      IconButton(
                        onPressed: () => _sendCommand(
                          'PlaybackCommand',
                          extra: {'action': 'NEXT'},
                        ),
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Playlist
          Expanded(
            child: ReorderableListView.builder(
              itemCount: _playlist.length,
              itemBuilder: (context, index) {
                final track = _playlist[index];
                return ListTile(
                  key: ValueKey(track['id']),
                  leading: SizedBox(
                    width: 40,
                    child: index == _currentIndex
                        ? const Icon(Icons.play_arrow)
                        : Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  title: Text(
                    track['title'],
                    style: index == _currentIndex
                        ? TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )
                        : null,
                  ),
                  subtitle: Text('${track['artist']} • ${track['album']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _sendCommand(
                      'PlaylistRemoveCommand',
                      extra: {'index': index},
                    ),
                  ),
                );
              },
              onReorder: (oldIndex, newIndex) {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                _sendCommand(
                  'PlaylistMoveCommand',
                  extra: {
                    'fromIndex': oldIndex,
                    'toIndex': newIndex,
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionController.dispose();
    widget.channel.sink.close();
    super.dispose();
  }
}