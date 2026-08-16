# 移动端播放器控制栏与菜单重构设计

日期：2026-08-16
范围：手机/平板触屏播放器（`PlayerControls`，`compact == true`）

## 背景

移动端竖屏控制栏中，播放键位于「播放组」中心，但播放组只在右侧按钮（选集/全屏/更多）之外的剩余空间内居中，导致播放键明显偏离屏幕几何中心。同时「更多」按钮弹出菜单把所有倍速档位平铺在菜单里，既占空间又和字幕列表（居中卡片面板样式）不一致；音轨仍用底部弹窗、字幕偏移用 AlertDialog，风格不统一。

## 目标

1. 竖屏控制栏播放键精确居中。
2. 「更多」菜单统一为字幕面板样式：倍速改为单行入口（显示当前值 + 箭头），点击进入子菜单调节。
3. 移动端所有菜单（更多/倍速/音轨/字幕/字幕偏移）统一为字幕面板样式（居中深色圆角卡片、48px 行、选中金色 ✓）。

## 设计

### 1. 竖屏控制栏：播放键精确居中

`_buildCompactTransportRow` 的竖屏分支改为 `Stack`：

- 底层：`Align(center)` 包裹居中的三键播放组 `[↶10] [▶播放] [10↷]`（`FittedBox` 防溢出）。
- 顶层：`Align(centerRight)` 放右侧按钮组（选集 / 全屏 / 更多）。

结果：播放键落在屏幕几何中心，左右视觉平衡；右侧按钮始终贴右，小屏不溢出。竖屏下播放组不再内联「上一集/下一集」（选集列表已覆盖剧集切换），保持三键紧凑居中。

### 2. 统一的菜单面板组件

新增 `lib/widgets/player/player_menu_sheet.dart`：

- `PlayerMenuRow`：`label` / `value`（行尾当前值文本）/ `selected` / `onTap` / `children`（子菜单行）/ `sectionTitle`（分组头）。
- `PlayerMenuSheet`（StatefulWidget）：维护页内导航栈；头部含返回箭头（栈深>1 时）、标题、计数、关闭按钮；行点击有 `children` 则推入子菜单页（带横向滑入过渡），否则执行 `onTap`。
- 视觉与 `PlayerSubtitlePanel` 完全一致：`0xEE101010` 底、16 圆角、48px 行、行分隔线 `0x18FFFFFF`、选中 `0x18FFFFFF` 高亮 + 金色（`#FFD54F`）✓、行尾箭头 `0xFFFFFF66`。
- 尺寸同字幕面板：宽 `size.width*0.72` 截断 300–400，高 `屏高 - 安全区 - 24`。

### 3. 「更多」菜单

`_buildCompactMoreButton` 由 `PopupMenuButton` 改为普通图标按钮，点击打开统一面板（`showGeneralDialog` + 淡入），主页 4 行：

| 行 | 值 | 子菜单 |
|----|----|--------|
| 倍速 | 当前倍速（如 `1.0x`） | 7 档倍速列表，选中 ✓，点选后 `setRate` 并关面板 |
| 音轨 | 当前音轨名 | 音轨列表（替换原底部弹窗 `_showAudioTrackPicker`） |
| 字幕 | 当前字幕名 | 复用字幕面板行构建逻辑 |
| 字幕偏移 | 当前偏移（如 `+0.0s`） | 提前 0.1s / 延后 0.1s / 精确调节（打开原偏移滑杆弹窗） |

### 4. 字幕/音轨/偏移入口统一

- 新增 `_buildSubtitleMenuRows(tracks, currentSub)`：把 `_showSubtitlePicker` 中「关闭/自动/内嵌/外挂」的行构建逻辑抽取为 `List<PlayerMenuRow>`（含分组头），供「更多」子菜单与独立字幕按钮复用。
- `_showSubtitlePicker`、`_showAudioTrackPicker` 改走统一面板，视觉一致。
- 字幕切换仍走既有 `SubtitleSwitchQueue` / `_onSubtitleMenuSelected` 链路，保留 `_containerCache` 防 auto-hide 销毁。

### 5. 不改动范围

- TV（D-Pad）布局的 `_showTvXxxPicker`、横屏内联控制、桌面端不变。
- `player_subtitle_panel.dart` 中 `PlayerSubtitlePanel` 保留（若不再被引用则删除并迁移到新组件）。

## 验收

- 竖屏：播放键居中；右侧选集/全屏/更多不变。
- 更多菜单：4 行、显示当前值+箭头；倍速点击进入子菜单，选档后生效并关闭。
- 音轨/字幕/偏移菜单与字幕面板样式一致。
- `flutter analyze` 通过。
