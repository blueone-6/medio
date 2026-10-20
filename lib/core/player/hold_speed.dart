/// Playback rate applied while the user holds the right half of the phone
/// screen to fast-forward, and restored on release.
///
/// Kept at 2x: the native player pitch-corrects this range (Sonic), so dialogue
/// stays intelligible, and it is slow enough that the release position is easy
/// to judge. The user's own speed choice (1x / 1.5x / …) is untouched — the
/// boost is temporary and never written back to settings.
const double holdFastForwardRate = 2.0;
