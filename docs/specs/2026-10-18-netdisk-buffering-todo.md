# TODO: 网盘中继「有效供给不足」排查（2026-10-18 晚）

状态：**单飞去重 + 预取已落地并验证有效，但缓冲未根治**。下一步需要
route 归属日志（已加进代码，还没抓过带 route 的数据）。

## 已完成并验证的修复（本次提交）

1. **per-block single-flight**（`netdisk_transport.dart`）
   - 改前：同一 4MB 块被 2-4 条连接重复下载，实测重复比 2.2×。
   - 改后：实测 0 重复（两段 150s+ 窗口、共 1500+ fetches）。
2. **块预取**（`prefetchDepth=2`，每块服务完即预拉后续 2 块）
   - 消除了串行「取 4MB → 服务 → 再取」的空转。
3. **每文件并发上限** `maxInflightPerFile=8`（从 3 调上来；3 时 4 条流互相挤占）。
4. **`_recent` LRU 容量 8**：无磁盘缓存时预取结果不被提前逐出。
5. **unregister 时 force-close 旧路由连接**：re-bootstrap 后的僵尸 relay
   不再偷带宽。
6. **每路由共享 HttpClient**：跨块复用 TCP。
7. **块缓存新增 `exists()`**（stat-only），预取前跳过已缓存块。
8. 新诊断：`block #N 206 bytes=… total=…ms route=<cacheKey>`、
   `relay #N route=<cacheKey> range=…`、`prefetch cap reached`（logcat 可见）。

测试：`test/netdisk_transport_test.dart` + `netdisk_block_cache_test.dart`
共 20 用例（新增 4 个：并发共享单飞、预取触发、预取不越界、exists）。

## 未解决的核心现象（需要下一轮）

手机播 4K remux，仍然每 **~20-30 秒**缓冲一次（TvExoPlayer state=2→3 循环），
与传输层健康数据矛盾：

- 传输层聚合供给稳定 **62-66 Mbps**，0 重复、0 失败、无慢块告警；
- 但播放器缓冲水位永远只涨到 **5-6 秒**（LoadControl 目标 30s/320MB），
  说明**有效视频供给 ≈ 消费码率**，没有余量；
- 换算：READY 期间缓冲以 ~0.45s/s 速率漏光 → 供给 ≈ 消费的 55-60%；
  若聚合 63Mbps 全是有效数据，等效码率 ~100Mbps —— 30GB/2.75h 的 remux
  应该只有 ~24Mbps。**矛盾指向：聚合带宽里只有约 1/4 到达视频解码器。**

### 关键疑点：4 条并行流各拿 ~15Mbps

用块号推进速率恢复出 4 条并发流（同一会话）：
- #3438..#3702 与 #4666..#4924：**同速推进、相隔 4.9GB**（各 265/259 块）
- #99..#218、#473..#616：较短的两条

同一文件的不同 offset 被同时顺序读取。若其中 2-3 条是冗余连接
（同一文件的僵尸 reader / 重复的 bootstrap 实例），则 ~30-45Mbps 被浪费，
视频实际只有 ~15Mbps < 码率 → 缓冲水位永远起不来。**这与所有观测一致，
但尚无 route 归属证据**。

### 下一步（按顺序）

1. **装当前构建抓一段带 route 的日志**（本次已加
   `MEDIO-TRANSPORT relay #N route=<cacheKey> range=…`）：
   ```powershell
   adb logcat -v time > cap.txt   # 播 2-3 分钟，覆盖至少 3 次缓冲
   ```
   用 `block … route=` 行按 route 分组算各文件吞吐（JS 分析脚本思路见
   git log 本提交），回答：4 条流是 1 个文件还是多个文件？
2. **若同一文件多连接**：定位多余连接来源 —
   - ExoPlayer re-bootstrap 时旧实例未 dispose（查 `exo_player_screen.dart`
     settle/recovery 路径的 player 释放）；
   - MKV cues/尾部读取（range 起点在文件尾部的连接是嫌疑）；
   - 缓解：播放中把非当前 route 的 relay 限速或直接拒绝第二个视频连接
     （transport 层加「活跃 relay 计数」日志先确认）。
3. **若多文件但视频只有 15Mbps**：提高视频流的并发（per-route 而非
   per-file 计数的 inflight 预算），或 prefetchDepth 2→3。
4. **兜底**：若码率实测 >100Mbps（`block route=` 吞吐 ÷ 消费速率估算），
   网络侧无法支撑直通，走 Emby 转码档。

### 测量陷阱（勿重蹈）

- logcat 的 tag 是 `TvExoPlayer(25200)`，不是 `TvExoPlayer:` ——
  过滤串写错会得到假阴性（曾误报「0 次缓冲」，实际 17 次）。
  正确：`Select-String -Pattern "TvExoPlayer.* state="`。
- release 包的 AppLog 文件在应用私有目录，`run-as` 不可用（非 debuggable）；
  **所有关键诊断必须走 debugPrint→logcat**。
- PowerShell 转义 `$`/反引号极脆弱；复杂分析用 node 脚本文件。
