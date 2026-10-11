# 网盘传输层韧性重构设计（统一代理 + 磁盘块缓存 + 重连）

日期：2026-10-11
范围：strm/网盘直链播放（全部平台：Windows 桌面、Android 手机、Android TV）

## 背景

当前 strm/网盘播放的韧性靠「播放器报错 → 守卫检测 → 整轮 re-bootstrap 重开」实现，链条长且脆弱：

- 播放器分两条传输路径：115 直连（`http-header-fields` 注入 header）、Quark 经 `NetdiskRangeProxy` 有界分块代理（`lib/core/player/netdisk_range_proxy.dart`）。
- 签名 URL 过期、CDN 限速、Range 失败只在**播放器层**暴露，随后由一堆守卫兜底：`bogus_position_guard.dart`、`seek_verification.dart`、stall detector、`reopen_backoff.dart`。这些守卫只能事后补救，无法覆盖所有情况——重开会丢位置、触发重连风暴、把正常播放误判为失败（生产日志多次出现）。
- 「重解析」目前是重量级的整轮 `PlaybackInfo → resolve → reopen`，代价高。

结论：把韧性**下沉到传输层**。既然全部网盘流都汇入一个本机代理，就可以在代理里就地吸收过期/限速/Range 失败，并加一层跨会话磁盘块缓存，让守卫基本不再触发。

## 目标

1. **统一传输层**：所有网盘/strm 播放都经 `NetdiskTransport`（由 `NetdiskRangeProxy` 升级），由它统一负责各家 CDN 的 header、有界 Range、以及被动重解析。
2. **被动重解析**：仅当上游对某段 Range 返回 `401/403/410` 或连接重置/超时，才刷新 URL+header 并重试同一段。
3. **磁盘块缓存**：代理把取到的字节按固定块落盘，后续 Range/seek/重试命中本地；跨平台一套逻辑（mpv 与 ExoPlayer 同时受益）；容量用户可配、按平台给默认值。
4. **重连**：代理→CDN 这一段在 Dart 侧做重连；非代理路径（Emby 自托管直连流）保留 mpv `stream-lavf-o` 重连选项。

## 非目标

- 不改播放器 UI。
- **不删除**现有守卫；作为最后一道防线保留，目标是让它们基本不再触发（后续用日志/埋点验证触发率）。
- 不新增第三方依赖（`path_provider` 已在依赖中）。
- Emby 自托管的普通直连/转码流**不**走代理，保持现状。

## 术语

- **传输层 / Transport**：本机 `NetdiskTransport` 单例 HTTP 服务。
- **路由 / Route**：一次播放注册的上游映射（上游 URL + header + 缓存键 + 重解析回调）。
- **块 / Block**：磁盘缓存的固定大小单元（4MB，与现有 `chunkSize` 一致）。
- **内容键 / cacheKey**：稳定内容标识，跨重解析、跨会话不变。

## 设计

### 架构总览

```
mpv / ExoPlayer --HTTP(Range)--> 127.0.0.1:PORT/<id> --> NetdiskTransport
                                                          |
                                          +---------------+---------------+
                                          v                               v
                                    NetdiskBlockCache               上游 HttpClient
                                    (命中 -> 本地回吐)         (未命中/需重解析 -> CDN
                                          ^                     或 Emby /stream 跟随 307)
                                          +-------- 写入新取到的块 --------+
```

### 组件 A：`NetdiskTransport`（`lib/core/player/netdisk_transport.dart`）

由 `netdisk_range_proxy.dart` 升级并改名。仍是单例、仍 `HttpServer.bind(loopbackIPv4, 0)`、仍返回 `http://127.0.0.1:<port>/<id>`。

路由模型 `_ProxyRoute` 扩展：

| 字段 | 说明 |
|------|------|
| `upstreamUrl` | 初始上游 URL（预解析的 CDN URL，或 Emby `/stream` URL） |
| `headers` | 上游请求 header（按 CDN 分类，见 `external_cdn_headers.dart`） |
| `cacheKey` | 稳定内容键（屏幕传入 `itemId` + `mediaSourceId`） |
| `refresh` | `Future<ResolvedStreamTarget> Function()?`，被动重解析回调 |

注册 API：

```dart
Future<String> register({
  required String upstreamUrl,
  Map<String, String>? headers,
  required String cacheKey,
  Future<ResolvedStreamTarget> Function()? refresh,
});
```

请求处理（`GET`/`HEAD`）：

1. 解析客户端 `Range: bytes=start-end`（缺省从头）。
2. 计算 `[start,end]` 覆盖的块集合；命中的块从磁盘回吐。
3. 未命中的块按 `chunkSize` 发有界上游请求（带 `Range`、header、`Accept-Encoding: identity`）。
4. 收到 `401/403/410` 或连接失败时，若该段**尚无字节回吐**（避免半段拼接错误），调用 `refresh()` 换新 URL+header 后重试同一段；refresh 带冷却与次数上限，避免风暴。
5. 取到的块先写盘再回吐（顺序写）。
6. 上游整体返回（非 206）时按整段处理，不无限循环。

**跟随 307**：把 Emby `/stream` URL 交给代理时，由 `HttpClient`（`followRedirects=true`, `maxRedirects=5`）在代理内部跟随跳转。115 的 UA 绑定由「代理发起的请求 UA == 预解析 UA == `AppConfig.httpUserAgent`」保证。因此播放器侧 `emby_307` 模式消失。

**纯函数下沉**（遵循 AGENTS.md，放 `lib/core/player/` 且可单测）：

- `netdisk_range_plan.dart`：`resolveRangeRequest(rangeHeader, total)`、`blockIndicesFor(start, end, blockSize)`。
- `netdisk_recovery.dart`：`shouldReResolve({statusCode, hasWrittenBytes, refreshAttempts})`、`reResolveCooldown(attempt)`。

### 组件 B：磁盘块缓存（`lib/core/player/netdisk_block_cache.dart`）

- `Future<Uint8List?> read(cacheKey, blockIndex)` / `Future<void> write(cacheKey, blockIndex, bytes)`。
- 落盘布局：`<cacheRoot>/netdisk/<cacheKey>/<blockIndex>.blk`（块大小 4MB）。
- **LRU 用文件 mtime 实现**：写盘即更新 mtime；超上限时按 mtime 从旧到新删除，直到回到上限内。不引入索引库/新依赖。
- **启动/退出清扫**：删除孤儿块目录与超上限块。
- 容量限制通过 `SettingsService` 配置（见下）。
- 纯函数：`blocksToEvict(entries, capBytes)`（`netdisk_cache_eviction.dart`）。

设置（`SettingsService` 新增）：

| 键 | 类型 | 默认（桌面 / 手机 / TV） |
|----|------|--------------------------|
| `netdiskCacheEnabled` | bool | true / true / **false** |
| `netdiskCacheLimitMb` | int | 5120 / 2048 / 1024 |

平台默认由纯函数 `defaultNetdiskCacheLimitMb(platform)` / `defaultNetdiskCacheEnabled(platform)` 决定，便于测试。

**缓存键必须跨重解析稳定**：签名 URL 每次重解析都会变，键只能用内容身份（`itemId` + `mediaSourceId`），绝不用整条 URL。

### 组件 C：重连（事项 3 重新定位）

- **代理→CDN 段（主）**：在 `NetdiskTransport` 的上游 `HttpClient` 里做连接重试（沿用 `reopen_backoff.dart` 式退避 + 连接超时）。
- **mpv 层（次要，仅非代理路径）**：`lib/core/player/player_http_headers.dart` 新增 `stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=7`。注意：
  - 放在 `stream-lavf-o`（不是 `demuxer-lavf-o`，后者会被 `applyExternalCdnPlaybackOptions` 清空；现有 115 Referer 逗号问题只在 `stream-lavf-o=headers=...` 时出现，reconnect 值内无逗号，安全）。
  - 实现时需实测确认该选项在本项目 mpv 版本下生效；不生效则以代理侧重连为准。
- 已有 `network-timeout=60` 保留。

### 屏幕接线

- `player_screen.dart`：把 `_openStrmPlayback` 中的 `cdn_direct` / `cdn_proxy` / `emby_307` 三分支合并为一次注册：

```dart
final local = await NetdiskTransport.instance.register(
  upstreamUrl: picked ?? embyStreamUrl,
  headers: <按 CDN 分类得到的 header>,
  cacheKey: '$itemId/$mediaSourceId',
  refresh: () => emby.reResolveCdnTarget(embyStreamUrl),
);
```

- `tv_player_screen.dart`：`_proxyUrlForStrm` 同样合并为注册调用（ExoPlayer 获得同一个本机 URL + 缓存键）。
- `emby_service.dart`：新增 `reResolveCdnTarget(embyStreamUrl)`，复用 `resolvePlaybackRedirectChain`，返回 `ResolvedStreamTarget{url, headers}`。
- `external_cdn_headers.dart`：`classifyExternalCdnUrl` 保留；把现有 `externalCdnPlaybackHttpHeadersForUrl` 收敛为 `headersFor(url)`，把「哪种 CDN 用什么 header」集中一处。分块抓取随磁盘块缓存天然按块对齐，不再需要按 CDN 的 Range 开关。

### 守卫处置

保留全部现有守卫，不改行为。新增日志/埋点记录守卫触发次数，用于验证结构韧性上去后触发率下降。若长期零触发，另立规格再删。

## 数据流

1. **首次播放**：屏幕注册路由 → 播放器打开本机 URL → 代理未命中 → 上游分块取 + 写盘 → 回吐。
2. **中途签名过期**：代理对某段收到 403 → `refresh()` 换新 URL+header → 重试同段 → 成功，播放器无感。
3. **二次播放/拖回已看位置**：代理从磁盘命中（键稳定）→ 不走网络。
4. **预解析失败**：上游 = Emby `/stream`，代理内部跟随 307 到 CDN，header 用 115 分类。

## 边界与错误处理

- 上游忽略 Range 返回整文件：单次流式转发，不进入分块循环。
- refresh 连续失败：达上限后向上游返回错误，交由现有守卫/错误 UI 处理。
- 磁盘写失败/空间不足：降级为不回写（仍正常回吐字节），记日志。
- 缓存已满且无法淘汰：停止写盘，不影响播放。
- 并发：同一 `cacheKey` 的多块读写串行化，避免半块。

## 测试策略

- **纯函数单测**：`resolveRangeRequest`、`blockIndicesFor`、`shouldReResolve`、`reResolveCooldown`、`blocksToEvict`、`defaultNetdiskCacheLimitMb/Enabled`、缓存键稳定性。
- **集成**：扩展 `test/live_emby_playback_test.dart`（opt-in，需真实 go-emby2openlist）：
  - 403 → 重解析 → 重试成功；
  - 同一 item 二次播放命中磁盘；
  - seek 至已缓存区域不走网络（用上游计数器断言）。
- **回归**：`flutter analyze` + `flutter test` 全绿。

## 风险与回滚

- 风险：块缓存并发写；TV 小存储被占满（默认关缓存缓解）；多一层跳转的延迟（loopback 可忽略）。
- 回滚：设置关缓存 + 保留「关代理走直连」开关，可退回现状。

## 备选方案（已否）

1. 保留 115 直连 + 仅针对性加重解析：路径分裂、直连 115 仍靠守卫。
2. 播放器原生盘缓存（mpv `--cache-on-disk` + ExoPlayer `SimpleCache`）：两套逻辑、跨会话不命中、未统一传输层。
3. 主动预刷新（解析 TTL）：依赖各家 URL 格式、维护成本高；本期只做被动。

## 验收

1. 全部网盘/strm 播放经本机代理，播放器侧不再有 `emby_307` 分支。
2. 签名过期时播放器无感（无重开、无守卫触发）。
3. 同一内容二次播放/拖回已缓存区域命中磁盘；容量到顶按 LRU 淘汰。
4. 缓存容量用户可配，平台默认符合上表；关闭后完全不打盘。
5. `flutter analyze` + `flutter test` 全绿；守卫触发率日志可见。
