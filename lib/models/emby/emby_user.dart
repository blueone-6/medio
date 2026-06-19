/// Emby / Jellyfin authenticated user summary.
class EmbyUser {
  const EmbyUser({
    required this.id,
    required this.name,
    this.serverId,
  });

  final String id;
  final String name;
  final String? serverId;

  factory EmbyUser.fromJson(Map<String, dynamic> json) {
    return EmbyUser(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      serverId: json['ServerId'] as String?,
    );
  }
}
