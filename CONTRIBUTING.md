# Contributing to Medio

Thanks for your interest in contributing! This guide covers the basics.

## Getting Started

1. Fork the repository and clone your fork.
2. Run `flutter pub get` to install dependencies.
3. Create a feature branch: `git checkout -b feat/your-feature`.

## Development Workflow

### Code Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines.
- Run `flutter analyze` before committing — it must pass with zero issues.
- Use `const` constructors where possible (enforced by lints).
- Avoid `print()`; use proper logging.

### Project Context

Before any UI work, read these design specs at the project root:

- **`PRODUCT.md`** — register, users, brand personality, design principles
- **`DESIGN.md`** — color/typography/elevation tokens, components, do's and don'ts
- **`AGENTS.md`** — project conventions and architecture

### Platform Targets

Medio targets three platforms equally:

| Platform | Player | Notes |
|----------|--------|-------|
| Windows Desktop | media_kit (libmpv) | `PlayerScreen` |
| Android Phone | media_kit (libmpv) | `PlayerScreen` |
| Android TV | ExoPlayer (Media3) | `TvPlayerScreen`, D-Pad navigation |

When adding UI, verify the experience makes sense on all applicable platforms.

### Commits

- Write clear, concise commit messages.
- Reference issues in commits when relevant (e.g., `Fix #123`).

## Pull Requests

1. Ensure `flutter analyze` passes.
2. Ensure `flutter test` passes (add tests for new logic where applicable).
3. Fill out the PR template.
4. Keep PRs focused — one feature or fix per PR.

## Reporting Issues

Use the GitHub Issue templates (Bug Report / Feature Request). Provide as much detail as possible, including:

- Platform and app version
- Steps to reproduce
- Expected vs. actual behavior

## License

By contributing, you agree that your contributions will be licensed under the [GPL-3.0-or-later](LICENSE).
