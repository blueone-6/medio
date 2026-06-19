import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/emby_provider.dart';
import '../../providers/home_hub_section_provider.dart';
import '../../providers/home_recommendation_provider.dart';

/// Refresh home lists after the player route pop settles.
///
/// Invalidating during [State.dispose] races the transition and can leave TV
/// home blank/crashed.
void schedulePlayerHomeDataRefresh(ProviderContainer container) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      try {
        container.invalidate(embyResumeProvider);
        container.invalidate(homeHubSectionProvider('recent'));
        container.invalidate(homeRecommendationProvider);
      } catch (_) {}
    });
  });
}
