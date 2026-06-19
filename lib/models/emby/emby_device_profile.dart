import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// Builds the Emby/Jellyfin [DeviceProfile] sent with `PlaybackInfo`.
///
/// Android uses a conservative audio profile (no TrueHD/DTS-HD direct play).
/// Video stays direct-play capable — Android TV uses ExoPlayer hard decode;
/// phone/desktop use mpv. Server transcoding is not required for 4K direct play.
Map<String, dynamic> buildEmbyDeviceProfile({bool? android}) {
  final onAndroid =
      android ?? (defaultTargetPlatform == TargetPlatform.android);
  return onAndroid ? _androidMpvProfile() : _desktopMpvProfile();
}

List<Map<String, dynamic>> _sharedSubtitleProfiles() => [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
    ];

Map<String, dynamic> _hlsVideoTranscodeProfile() => {
      'Container': 'ts',
      'Type': 'Video',
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'Protocol': 'hls',
      'EstimateContentLength': false,
      'EnableMpegtsM2TsMode': false,
      'TranscodingSeekInfo': 'Auto',
      'CopyTimestamps': false,
      'Context': 'Streaming',
      'MaxAudioChannels': '6',
      'MinSegments': 2,
      'BreakOnNonKeyFrames': true,
    };

Map<String, dynamic> _httpVideoTranscodeProfile() => {
      'Container': 'mp4',
      'Type': 'Video',
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'Protocol': 'http',
      'EstimateContentLength': false,
      'EnableMpegtsM2TsMode': false,
      'TranscodingSeekInfo': 'Auto',
      'CopyTimestamps': false,
      'Context': 'Streaming',
      'MaxAudioChannels': '6',
      'MinSegments': 0,
      'BreakOnNonKeyFrames': false,
    };

Map<String, dynamic> _audioTranscodeProfile() => {
      'Container': 'mp3',
      'Type': 'Audio',
      'AudioCodec': 'aac',
      'Protocol': 'http',
      'EstimateContentLength': false,
      'EnableMpegtsM2TsMode': false,
      'TranscodingSeekInfo': 'Auto',
      'CopyTimestamps': false,
      'Context': 'Streaming',
      'MaxAudioChannels': '2',
      'MinSegments': 0,
      'BreakOnNonKeyFrames': false,
    };

Map<String, dynamic> _androidMpvProfile() {
  const videoCodecs = 'h264,hevc';
  // mpv on Android lacks TrueHD/DTS-HD MA decoders — keep to common passthrough codecs.
  const audioCodecs = 'aac,ac3,eac3,mp3,opus,flac,vorbis,alac';

  return {
    'Name': 'Media Client Android',
    'MaxStaticBitrate': 140000000,
    'MaxStreamingBitrate': 140000000,
    'MusicStreamingTranscodingBitrate': 384000,
    'DirectPlayProfiles': [
      {
        'Container': 'mp4,m4v,mov',
        'Type': 'Video',
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
      {
        'Container': 'mkv',
        'Type': 'Video',
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
      {
        'Container': 'ts,mpegts',
        'Type': 'Video',
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
      {
        'Container': 'mp3,aac,flac,ogg,wav',
        'Type': 'Audio',
        'AudioCodec': audioCodecs,
      },
    ],
    'TranscodingProfiles': [
      _hlsVideoTranscodeProfile(),
      _httpVideoTranscodeProfile(),
      _audioTranscodeProfile(),
    ],
    'CodecProfiles': [],
    'ContainerProfiles': [],
    'SubtitleProfiles': _sharedSubtitleProfiles(),
  };
}

Map<String, dynamic> _desktopMpvProfile() {
  const videoCodecs = 'h264,hevc,vp9,av1';
  const audioCodecs =
      'aac,ac3,eac3,mp3,opus,flac,vorbis,alac,dts,truehd,mlp';

  return {
    'Name': 'Media Client',
    'MaxStaticBitrate': 999999999,
    'MaxStreamingBitrate': 999999999,
    'MusicStreamingTranscodingBitrate': 192000,
    'DirectPlayProfiles': [
      {
        'Container': 'mp4,m4v,mov,mkv,ts,mpegts,webm',
        'Type': 'Video',
        'VideoCodec': videoCodecs,
        'AudioCodec': audioCodecs,
      },
      {
        'Container': 'mp3,aac,flac,ogg,wav',
        'Type': 'Audio',
        'AudioCodec': audioCodecs,
      },
    ],
    'TranscodingProfiles': [
      _hlsVideoTranscodeProfile(),
      _httpVideoTranscodeProfile(),
      _audioTranscodeProfile(),
    ],
    'CodecProfiles': [],
    'ContainerProfiles': [],
    'SubtitleProfiles': _sharedSubtitleProfiles(),
  };
}
