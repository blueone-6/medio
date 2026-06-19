/// Pass-through gesture layer on non-IO platforms.
library;

export 'player_gesture_stub.dart'
    if (dart.library.io) 'player_gesture_mobile.dart';
