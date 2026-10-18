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

## release + R8 白屏（已定位并修复）

症状：`isMinifyEnabled = true` 的 release 包首帧永不出、纯白，进程不崩；debug 与关掉
R8 的 release 正常。

**定位方法**：release 里 Dart 侧没有任何可读日志（`AppLog` 只在 `kDebugMode` 打
logcat，应用私有日志目录在非 debuggable 包上 `run-as` 不可用）。临时在 `main()`
每个 await 后打 breadcrumb，并通过一个一次性 MethodChannel（`medio/boot_trace`）
落到原生 `Log.i`，第一次构建就打出：

```
MEDIO-BOOT device type detected
MEDIO-BOOT BOOT FAILED: PlatformException(... java.lang.NoSuchMethodError:
  no non-static method "Lio/flutter/plugins/sharedpreferences/
  SharedPreferencesApiRegistrar;.getAll(String, List, Continuation)Object")
```

即 `LocalStorage.open()` → `SharedPreferences.getInstance()` 抛异常，被
`CrashReporter.runZonedLogged` 的 zone 捕获（只写崩溃日志文件），`runApp()`
永不执行 → 白屏且无崩溃。

**根因**（两层，都来自实际参与构建的 `shared_preferences_android` **2.5.0** 改用
jnigen 直连 JNI，而不是 MethodChannel）：

1. **描述符被改写**：`@Keep` 保住了方法名，但描述符里的
   `kotlin.coroutines.Continuation` 被 R8 改名（mapping 里可见
   `(Ljava/lang/String;Ljava/util/List;LX1/d;)Ljava/lang/Object;` 以及
   `com.android.tools.r8.residualsignature`），而 Dart 侧是按**原描述符**
   `GetMethodID`；签名对不上 → `NoSuchMethodError`。
2. **按名字加载的类被剪掉**：`package:jni` 的 `lib/src/kotlin.dart` 用
   `JClass.forName('kotlin/coroutines/intrinsics/CoroutineSingletons')`、
   `IntrinsicsKt`、`Unit`、`Result`/`Result$Failure` 按名字取 Kotlin 运行时类，
   这些类没有静态引用，R8 直接删除 → `ClassNotFoundException`。
   上游 `jni` 的 `android/consumer-rules.pro` 只 keep 了
   `com.github.dart_lang.jni.**`，而且 **Flutter 插件是 Gradle 子工程、consumer
   rules 根本不会被应用**。

**修复**：`android/app/proguard-rules.pro` 增加两组规则
- `-keep, includedescriptorclasses` 两个 jnigen 插件包
  （`io.flutter.plugins.sharedpreferences.**`、`io.flutter.plugins.pathprovider.**`），
  保证描述符里的类型不被改名；
- `-keep` `com.github.dart_lang.jni.**` 与 jni 按名字加载的 Kotlin 类
  （`Continuation`、`CoroutineSingletons`、`IntrinsicsKt`、`Unit`、`Result`、
  `Result$Failure`）。

**验证**：release + R8 包真机启动走到 `first frame rendered`，首页正常、继续观看
历史仍在；logcat 无 `NoSuchMethodError` / `ClassNotFoundException` / `E/flutter`。
复现/回归检查流程：`flutter build apk --release` → `adb install -r` →
`adb shell am start -n com.medio.community/com.example.media_client.MainActivity` →
截图确认非白屏（白屏时截图只有 ~45KB，正常首页 ~1.9MB）。

**依赖锁漂移（已收敛）**：白屏是被它带进来的——本机 `PUB_HOSTED_URL` 指向
`https://pub.flutter-io.cn`，而提交的 `pubspec.lock` 里所有 hosted 包记的都是
`https://pub.dev`，pub 把「换了源」当成换了包，于是 `pub get` 重解析了 144 个依赖
（实际编译 `shared_preferences_android` 2.5.0，而 lock 里钉的是 2.4.23）。
把 User 级 `PUB_HOSTED_URL` 删掉
（`[Environment]::SetEnvironmentVariable('PUB_HOSTED_URL',$null,'User')`）之后，
`flutter pub get --enforce-lockfile` 直接通过、lock 零改动，解析回 2.4.23。

⚠️ **换依赖源 / 换版本后必须 `flutter clean`**：增量 Dart 编译器会留着旧的 2.5.0
kernel，而 Gradle 已按 2.4.23 编译 Java，于是得到「Dart 在找 jnigen 的
`SharedPreferencesApiRegistrar`、Java 侧根本没有」的混合包，
**debug 包同样抛 `ClassNotFoundException`**——很容易误判成 R8 问题（本次就先被
这个坑带偏了一轮）。清干净重建后，锁文件版本（2.4.23）release + R8 正常启动。

另外：2.4.23 走 MethodChannel，上面的 keep 规则对它是 no-op；依赖一旦再升到 2.5.x
规则立即生效（已在 2.5.0 上实测能启动）。

## 尚未处理 / 已知问题

1. **多机签名不一致**：手机上的 1.2.0 包用了一台本机没有的 keystore 签名，
   覆盖安装会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`；本次是卸载重装。
   建议按 `android/key.properties` 注释统一到一个共享 keystore。
2. **stale 判定的余量**：`staleGrace=6s` 期间、以及每次锚点切换后的判定窗口内，
   被放弃的 reader 仍会全速拉一会儿（实测峰值 ~100MB）。若要更激进可缩短
   `staleDropAfter`，或在 `register()` 被同一 cacheKey 重复调用时直接判旧 route 过期。
3. **transport 无法感知客户端半关连接**是本次的通用隐患：只要对端把响应读完丢弃，
   我们就永远不知道它已经走了。除 stale 判定外，可考虑给 open-ended 响应加
   「长时间无消费迹象」检测（例如统计 `flush()` 的阻塞时间分布）。
4. **pubspec.lock 与镜像**：已按上面「依赖锁漂移」一节收敛（用 pub.dev 时
   `flutter pub get --enforce-lockfile` 通过，锁零改动）。若以后确实必须用镜像，
   构建完记得 `git checkout -- pubspec.lock`，并先用 `--enforce-lockfile` 验证锁
   是否还成立，不要静默接受 144 个包的重解析。

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
- **依赖版本/来源变了以后 `flutter build` 不一定重编 Dart**：看到「Dart 在找某个
  Java 类、包里没有」的 `ClassNotFoundException`，先 `flutter clean`，
  否则会把它误判成 R8 剪裁（本次多花了一轮构建）。
- 白屏判据：`adb shell screencap` 拉回来的 PNG **~45KB = 空白页**，
  **~1.9MB = 正常首页**，不用人眼看图就能判断。
