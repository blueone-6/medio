/// A concrete, playable upstream target produced by (re-)resolving a netdisk
/// stream (an Emby `/stream` URL or a pre-resolved CDN URL).
///
/// Used as the return type of the transport's `refresh` callback so a signed
/// URL can be swapped mid-playback together with the headers it needs.
class ResolvedStreamTarget {
  const ResolvedStreamTarget({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;

  @override
  String toString() => 'ResolvedStreamTarget(url=$url, headers=${headers.keys.toList()})';
}
