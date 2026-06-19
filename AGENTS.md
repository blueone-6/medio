# Agent Context

## Project

Cross-platform Flutter media client (`medio`): Emby/Jellyfin library browsing on **Windows desktop**, **Android phone**, and **Android TV**. Playback: **Android TV** uses ExoPlayer (`TvPlayerScreen`, `lib/core/player/tv_exo/`); **phone / desktop** use `media_kit` (libmpv) via `PlayerScreen`.

## Design Context

Strategic and visual specs live at the project root. **Read both before any UI work:**

| File | Purpose |
|------|---------|
| [`PRODUCT.md`](PRODUCT.md) | Register, users, brand personality, anti-references, design principles |
| [`DESIGN.md`](DESIGN.md) | Color/typography/elevation tokens, components, do's and don'ts |

### Quick reference (from PRODUCT.md)

- **Register:** `product` (app UI serves the media workflow)
- **Users:** Self-hosted media enthusiasts; all three platforms equally important
- **Brand:** Dark · refined · immersive ("私人影院")
- **Anti-references:** Cheap Android video apps, generic SaaS dashboards, overloaded streaming UIs, AI template scaffolding
- **Principles:** Content-first; consistent across platforms with input-adapted interaction; cinema-grade playback trust; restrained premium feel; practical without looking cheap
- **A11y:** WCAG 2.1 AA, full TV D-Pad support, respect reduced motion

### Theme code entry points

- Tokens: `lib/core/theme/` (`app_theme.dart`, `app_colors.dart`, `app_spacing.dart`, `app_radius.dart`, `app_motion.dart`)
- TV focus: `lib/widgets/tv/`, `lib/core/tv/`
- Sidecar for design tooling: `.impeccable/design.json`

## Conventions

- Flutter + Riverpod + go_router; Material 3
- No new dependencies without explicit approval
- Run `flutter analyze` after UI changes
