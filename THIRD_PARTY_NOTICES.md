# Third-Party Notices

Medio incorporates the following third-party software. Each component is
distributed under its own license; the full text of every license is either
quoted below or available at the upstream URL referenced. The list reflects
the runtime dependencies bundled with the **Medio Community** Windows x64
build; non-bundled development tooling (Flutter SDK, Dart SDK) is mentioned
for completeness.

This file is provided to satisfy the attribution requirements of the GNU
General Public License v3 or later (under which Medio itself is distributed)
and the licenses of the components below. It does **not** grant any
additional rights.

---

## 1. Flutter & Dart SDK (build & runtime)

- Project: <https://flutter.dev>, <https://dart.dev>
- License: BSD 3-Clause License
- Copyright (c) 2014, the Flutter authors. All rights reserved.

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Google Inc. nor the names of its contributors
      may be used to endorse or promote products derived from this software
      without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

---

## 2. Dart / Flutter packages (pub.dev)

The following packages are linked into the application binary and are each
distributed under permissive licenses (BSD-3-Clause / MIT / Apache-2.0).
Full license texts are available in each package on <https://pub.dev>.

| Package | Version constraint | Upstream | License |
|---------|--------------------|----------|---------|
| `flutter_riverpod` | ^2.5.1 | <https://pub.dev/packages/flutter_riverpod> | MIT |
| `go_router` | ^14.2.0 | <https://pub.dev/packages/go_router> | BSD-3-Clause |
| `dio` | ^5.4.3+1 | <https://pub.dev/packages/dio> | MIT |
| `shared_preferences` | ^2.2.3 | <https://pub.dev/packages/shared_preferences> | BSD-3-Clause |
| `cached_network_image` | ^3.3.1 | <https://pub.dev/packages/cached_network_image> | MIT |
| `media_kit` | ^1.2.6 | <https://pub.dev/packages/media_kit> | MIT |
| `media_kit_video` | ^2.0.1 | <https://pub.dev/packages/media_kit_video> | MIT |
| `media_kit_libs_video` | ^1.0.7 | <https://pub.dev/packages/media_kit_libs_video> | MIT |
| `window_manager` | ^0.5.1 | <https://pub.dev/packages/window_manager> | MIT |
| `intl` | ^0.20.2 | <https://pub.dev/packages/intl> | BSD-3-Clause |
| `collection` | ^1.18.0 | <https://pub.dev/packages/collection> | BSD-3-Clause |
| `cupertino_icons` | ^1.0.8 | <https://pub.dev/packages/cupertino_icons> | MIT |
| `path` | ^1.9.0 | <https://pub.dev/packages/path> | BSD-3-Clause |
| `path_provider` | ^2.1.4 | <https://pub.dev/packages/path_provider> | BSD-3-Clause |
| `screen_brightness` | ^2.1.7 | <https://pub.dev/packages/screen_brightness> | MIT |
| `share_plus` | ^10.1.4 | <https://pub.dev/packages/share_plus> | BSD-3-Clause |

---

## 3. mpv / libmpv (`libmpv-2.dll`, `mpv-2.dll`)

- Project: <https://mpv.io>
- Source: <https://github.com/mpv-player/mpv>
- Build distribution: <https://sourceforge.net/projects/mpv-player-windows/files/libmpv/>
- License: **GNU General Public License, version 2 or later** (full GPL build
  used by Medio; this is the GPL ffmpeg variant)

The bundled `libmpv-2.dll` / `mpv-2.dll` files in `dist/medio-community-*-windows-x64.zip`
are unmodified copies of the upstream "GPL build" published by the mpv
maintainers. See `LICENSE` in the same archive for the full GPLv3 text under
which the resulting combined work is distributed; the upstream
`LICENSE.GPL` file (GPLv2) is reproduced at
<https://github.com/mpv-player/mpv/blob/master/LICENSE.GPL>.

`libmpv` itself dynamically links against, and is built on top of, the
following GPL/LGPL components (also redistributed inside the bundled DLL):

### 3.1 FFmpeg (GPL build)

- Project: <https://ffmpeg.org>
- License: GPLv2 or later (when built with `--enable-gpl`, which the bundled
  build uses)

### 3.2 Other libmpv dependencies

The mpv "GPL build" further bundles components such as `libass`, `zlib`,
`libplacebo`, `lcms2`, `libarchive`, `libdvdread`, `libdvdnav`,
`libbluray`, `dav1d`, `libfdk-aac` (if present), `lua`. Each retains its
upstream license (LGPL/GPL/MIT/BSD as applicable). The unmodified DLL is
the canonical artifact; consult <https://mpv.io/installation/> and the mpv
upstream `Copyright` file for the consolidated list.

---

## 4. Fonts

### 4.1 Be Vietnam Pro

- Project: <https://github.com/bettergui/BeVietnamPro>
- License: SIL Open Font License 1.1
- Files bundled: `assets/fonts/BeVietnamPro-{Regular,Medium,SemiBold,Bold}.ttf`

### 4.2 Noto Sans SC

- Project: <https://fonts.google.com/noto/specimen/Noto+Sans+SC>
- License: SIL Open Font License 1.1
- Files bundled: `assets/fonts/NotoSansSC-{Regular,Medium,Bold}.otf`

The full text of the SIL Open Font License 1.1 is available at
<https://openfontlicense.org>.

---

## 5. Application icon

`windows/runner/resources/app_icon.ico` is an original work distributed as
part of Medio under the same GPLv3-or-later terms as the rest of this
project.

---

## 6. Server protocols

Medio Community is an independently developed compatible client. It
interacts with self-hosted media servers using their documented HTTP APIs;
no server source code, trademarks, or proprietary client code from any
upstream media-server vendor is included in this binary.
