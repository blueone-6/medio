import 'package:collection/collection.dart';

import 'package:media_kit/media_kit.dart';



import '../logging/app_log.dart';

import '../../models/emby/emby_subtitle_option.dart';
import '../../services/emby_service.dart';
import 'apply_emby_subtitle.dart';
import 'player_subtitle_visibility.dart';

import 'subtitle_switch_queue.dart';
import 'subtitle_track_kind.dart';
import 'subtitle_track_match.dart';



/// Picks and activates a muxed subtitle track (text subrip and/or PGS).

Future<bool> selectEmbeddedSubtitle({

  required Player player,

  List<EmbySubtitleOption> embyOptions = const [],

  EmbySubtitleOption? prefer,

  EmbyService? emby,

  int? generation,

}) async {

  var all = player.state.tracks.subtitle
      .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
      .toList();
  if (all.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 24));
    all = player.state.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data)
        .toList();
  }



  if (all.isEmpty) {

    AppLog.instance.w('Subtitle', 'selectEmbedded: no muxed tracks');

    return false;

  }



  final playable = playableMuxedSubtitles(all);

  final pgsTracks = pgsMuxedSubtitles(all);

  AppLog.instance.i(

    'Subtitle',

    'selectEmbedded muxed=${all.length} text=${playable.length} pgs=${pgsTracks.length}',

  );



  SubtitleTrack? pick;

  if (prefer != null && !prefer.isExternal) {

    if (prefer.isBitmapSubtitle) {

      pick = matchMuxedSubtitleTrack(pgsTracks, prefer) ??
          matchMuxedSubtitleTrack(all, prefer);

    } else {

      pick = matchMuxedSubtitleTrack(playable, prefer) ??
          matchMuxedSubtitleTrack(all, prefer);

    }

  }

  pick ??= _pickFromEmbyDefaults(playable, embyOptions);
  pick ??= pickDefaultTextTrack(playable);



  if (pick != null) {
    if (emby != null && !isPgsMuxedSubtitle(pick)) {
      EmbySubtitleOption? opt;
      if (prefer != null &&
          !prefer.isExternal &&
          !prefer.isBitmapSubtitle &&
          prefer.format != 'pgs') {
        opt = prefer;
      } else {
        opt = embyTextOptionForMuxed(pick, embyOptions);
      }
      if (opt != null) {
        final gen = generation ?? SubtitleSwitchQueue.begin();
        final ok = await applyEmbySubtitle(
          player: player,
          option: opt,
          emby: emby,
          generation: gen,
        );
        AppLog.instance.i(
          'Subtitle',
          'selectEmbedded sub-add index=${opt.index} ok=$ok',
        );
        if (ok) return true;
      }
    }

    if (!isPgsMuxedSubtitle(pick)) {
      final opt = embyTextOptionForMuxed(pick, embyOptions) ?? prefer;
      if (opt != null && emby != null) {
        final gen2 = generation ?? SubtitleSwitchQueue.begin();
        final ok2 = await applyEmbySubtitle(
          player: player, option: opt, emby: emby, generation: gen2,
        );
        if (ok2) return true;
      }
      return false;
    }

    final ok = await player.activateMuxedSubtitle(
      pick,
      reason: 'selectEmbedded prefer=${prefer?.label}',
    );

    AppLog.instance.i(
      'Subtitle',
      'selectEmbedded pick=${pick.id} codec=${pick.codec} ok=$ok',
    );

    if (ok) return true;
    if (!isPgsMuxedSubtitle(pick)) return false;

  }



  // Preferred/default was PGS but activation failed — fall back to text.

  final fallback = pickDefaultTextTrack(playable) ?? playable.firstOrNull;

  if (fallback == null) {

    AppLog.instance.e('Subtitle', 'selectEmbedded: no text fallback');

    return false;

  }

  final opt = embyTextOptionForMuxed(fallback, embyOptions);
  if (opt != null && emby != null) {
    final gen2 = generation ?? SubtitleSwitchQueue.begin();
    final ok2 = await applyEmbySubtitle(
      player: player, option: opt, emby: emby, generation: gen2,
    );
    AppLog.instance.i(
      'Subtitle',
      'selectEmbedded fallback ${fallback.id} ${fallback.title} ok=$ok2',
    );
    return ok2;
  }

  final ok = await player.activateMuxedSubtitle(
    fallback,
    reason: 'selectEmbedded pgs_fallback',
  );

  AppLog.instance.i(
    'Subtitle',
    'selectEmbedded fallback=${fallback.id} ${fallback.title} ok=$ok',
  );

  return ok;

}



/// Maps a muxed [SubtitleTrack] to an Emby embedded text option when possible.
EmbySubtitleOption? embyTextOptionForMuxed(
  SubtitleTrack track,
  List<EmbySubtitleOption> embyOptions,
) {
  for (final o in embyOptions) {
    if (o.isExternal || o.isBitmapSubtitle || o.format == 'pgs') continue;
    final m = matchMuxedSubtitleTrack([track], o);
    if (m?.id == track.id) return o;
  }
  return null;
}

SubtitleTrack? _pickFromEmbyDefaults(

  List<SubtitleTrack> native,

  List<EmbySubtitleOption> embyOptions,

) {

  for (final o in embyOptions) {

    if (o.isExternal) continue;

    if (!o.isDefault && !o.isForced) continue;

    final pool = o.isBitmapSubtitle ? pgsMuxedSubtitles(native) : playableMuxedSubtitles(native);

    final m = matchMuxedSubtitleTrack(pool.isNotEmpty ? pool : native, o);

    if (m != null) return m;

  }

  return null;

}


