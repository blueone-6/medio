import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/emby/emby_person.dart';
import '../services/emby_service.dart';

class MediaCastSliver extends StatelessWidget {
  const MediaCastSliver({super.key, required this.people, required this.emby});

  final List<EmbyPerson>? people;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final list = people;
    if (list == null || list.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('演员表',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _CastRow(people: list, emby: emby),
          ],
        ),
      ),
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.people, required this.emby});

  final List<EmbyPerson> people;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final actors = people.where((p) => p.isActor).toList();

    if (actors.isEmpty) {
      return _buildList(context, people);
    }

    return _buildList(context, actors);
  }

  Widget _buildList(BuildContext context, List<EmbyPerson> list) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            _CastCard(person: list[i], emby: emby),
            if (i < list.length - 1) const SizedBox(width: 14),
          ],
        ],
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.person, required this.emby});

  final EmbyPerson person;
  final EmbyService emby;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const size = 72.0;

    String? imageUrl;
    if (person.id.isNotEmpty &&
        person.primaryImageTag != null &&
        person.primaryImageTag!.isNotEmpty) {
      imageUrl = emby.posterUrl(person.id,
          tag: person.primaryImageTag, maxHeight: AppConfig.posterMaxHeight ~/ 2);
    }

    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: emby.imageAuthHeaders,
                      fit: BoxFit.cover,
                      memCacheHeight: AppConfig.posterMaxHeight ~/ 2,
                      placeholder: (_, __) => Center(
                          child: Icon(Icons.person_rounded,
                              size: size * 0.35,
                              color: cs.outlineVariant)),
                      errorWidget: (_, __, ___) => Center(
                          child: Icon(Icons.person_rounded,
                              size: size * 0.35,
                              color: cs.outlineVariant)),
                    )
                  : Center(
                      child: Icon(Icons.person_rounded,
                          size: size * 0.35,
                          color: cs.outlineVariant)),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 8,
            child: Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface),
            ),
          ),
          if (person.role != null && person.role!.isNotEmpty)
            SizedBox(
              width: size + 8,
              child: Text(
                person.role!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
