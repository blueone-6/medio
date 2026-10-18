# TODO: 网盘中继「有效供给不足」排查（2026-10-18 晚）

状态：**根因已定位并修复，真机验证通过**（缓冲水位 2.5s → 50–80s）。

## 根因（日志实证）

播放器侧包了一层 `DataSource` 日志（`LoggingDataSourceFactory.kt`，tag `TvExoPlayer`，
行首 `ds#N`），配合 transport 的 relay 日志，得到结论：

```
23:06:20.774 ds#1 open pos=0            → close after 0MB alive=26ms     ← Media3 已放弃
23:06:21.796 ds#1 open pos=29524873577  → close after 0MB alive=79ms     ← 尾部 cues 探测
23:06:21.885 ds#1 open pos=7546         → close after 0MB alive=66ms     ← 头段探测
23:06:22.082 ds#1 open pos=14188825850  → 真正播放流（长时间读取）
```

- Media3 复用**同一个** DataSource，探测用的两条流 **26–79 ms 就 close 了、读了 0 字节**；
- 但 transport 侧对应的 relay 活了**几分钟**，持续从 CDN 全速拉数据：
  **客户端已经放弃连接，TCP 却没被真正关闭（对端仍在把我们的 200 响应读完丢弃），
  所以 `resp.flush()` 永不报错，transport 无从感知**；
- 每条僵尸 relay 都在空转吃带宽（按连接限速 ~10–13 Mbps），视频流只拿到 ~28 Mbps
  ≈ 码率，于是缓冲水位永远上不来、每 20–30 秒缓冲一次。

原先怀疑的「单飞去重没生效 / 预取不够」都不是主因：单飞去重一直是 0 重复。

## 本次修复

`lib/core/player/netdisk_transport.dart` + 新增 `netdisk_stale_reader.dart`：

1. **stale reader 判定**（`isStaleReader`，纯函数、可测）：同一文件里，若存在更新的
   reader，且某条旧 reader 距它 > 64MB、存活 > 6s，则判定为「播放器已离开的 reader」。
   短命探测（尾部/头段读取，<1s）不受影响；**判定加迟滞**——拖动换锚点后不会重置再全速拉。
2. **限速 + 最终切断**：stale reader 每块之间插入 8s 延迟（≈0.5 Mbps 量级）并停止预取；
   持续 stale 超过 30s 直接 `dropped` 关闭响应。
3. **预取窗口 2 → 4**（`prefetchDepth`）：僵尸流被限速后，单条播放流是唯一消费者，
   CDN 又按连接限速，窗口深度决定单流吞吐（实测 depth=2 只有 ~28 Mbps，正好等于码率）。
4. `_recent` 容量 8 → 12 以容纳新窗口。
5. 诊断：`relay #N rid=<路由id> ... ua=<客户端>`、`relay #N stale/dropped`、
   播放器侧 `buffer pos=..s ahead=..s state=` 每 5s 一行（都是 logcat 可见的裸 debugPrint）。

### 真机验证（4K remux，29.5GB，码率 ~28–34 Mbps）

| | 修复前 | 修复后 |
|---|---|---|
| 稳定播放缓冲水位 | 恒 2.5s | 24→31→44→48s（上限 90s） |
| 拖到冷区域后 | 1–5s 徘徊、~30s 一次缓冲 | 单调 1→11→25→42→53s，无二次缓冲 |
| 同文件并发 reader | 3–4 条全速 | 僵尸流 stale→限速→32s 后 dropped |

测试：`test/netdisk_stale_reader_test.dart`（5 例，含纯策略与端到端 stale/drop），
连同 `netdisk_transport_test.dart`、`netdisk_block_cache_test.dart` 共 26 例通过。

## 尚未处理 / 已知问题

1. **release + R8 白屏（本次排查中发现，独立问题）**：`isMinifyEnabled = true` 时
   release 包首帧不出、全白；把 `isMinifyEnabled`/`isShrinkResources` 关掉即正常
   （debug 包也正常）。疑似 R8 剪裁掉启动路径所需的东西，未定位到具体类；
   当前仓库保持原有 minify 配置，需要单独排查（可用 `-keep class io.flutter.**` 二分）。
   注意本机 `flutter pub get` 会重解析 144 个依赖（提交的 `pubspec.lock` 与当前 SDK
   约束不符），排查 R8 时先固定依赖集。
2. **多机签名不一致**：手机上的 1.2.0 包用了一台本机没有的 keystore 签名，
   覆盖安装会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`；本次是卸载重装。
   建议按 `android/key.properties` 注释统一到一个共享 keystore。
3. **stale 判定的余量**：`staleGrace=6s` 期间、以及每次锚点切换后的判定窗口内，
   被放弃的 reader 仍会全速拉一会儿（实测峰值 ~100MB）。若要更激进可缩短
   `staleDropAfter`，或在 `register()` 被同一 cacheKey 重复调用时直接判旧 route 过期。
4. **transport 无法感知客户端半关连接**是本次的通用隐患：只要对端把响应读完丢弃，
   我们就永远不知道它已经走了。除 stale 判定外，可考虑给 open-ended 响应加
   「长时间无消费迹象」检测（例如统计 `flush()` 的阻塞时间分布）。

## 测量陷阱（勿重蹈）

- logcat 的 tag 是 `TvExoPlayer(25200)`，不是 `TvExoPlayer:` ——
  过滤串写错会得到假阴性（曾误报「0 次缓冲」，实际 17 次）。
  正确：`Select-String -Pattern "TvExoPlayer.* state="`。
- release 包的 AppLog 文件在应用私有目录，`run-as` 不可用（非 debuggable）；
  且 `AppLog` 只在 `kDebugMode` 才 `debugPrint`（`app_log.dart:449`），
  **release 里 Dart 侧一条日志都不出**——关键诊断必须走裸 `debugPrint`。
  `MEDIO-TRANSPORT` 与新的 `ds#N`/`buffer` 日志都是裸 `debugPrint`。
- `adb shell kill -3 <pid>` 对应用进程报 `Operation not permitted`；
  要抓 Java 线程栈得用 debuggable 包 + `adb shell run-as <pkg> kill -3`（本次 sink 未落 logcat，
  最终是靠 DataSource 包装日志定的性）。
- `flutter run` 会先卸载旧包，且 vivo 息屏时会直接拒绝 adb 安装
  （`INSTALL_FAILED_ABORTED: User rejected permissions`）：先 `adb shell input keyevent 87` 唤醒。
- PowerShell 转义 `$`/反引号极脆弱；日志分析用 `tool/analyze_transport_log.js`
  （按 route 分组：吞吐、重复块、连续读流、并发 relay、10s 桶、缓冲水位）。
