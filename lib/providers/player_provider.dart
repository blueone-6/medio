import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

/// Exposes [Player] from [playerServiceProvider] for widgets that need it.
final playerProvider = Provider(
  (ref) => ref.watch(playerServiceProvider).player,
);
