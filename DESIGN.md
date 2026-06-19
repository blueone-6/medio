---
name: Medio Community
description: 暗色沉浸的跨平台自托管流媒体客户端视觉系统
colors:
  canvas-dark: "#131315"
  canvas-light: "#F5F5F7"
  ink-primary: "#E5E1E4"
  ink-secondary: "#9898A2"
  ink-primary-light: "#1A1A1E"
  accent-cinema-gold: "#FFDCA1"
  accent-cinema-gold-deep: "#FFB800"
  surface-raised: "#2A2A2C"
  surface-container: "#1F1F21"
  play-cinema-green: "#43A047"
  scrim-overlay: "#0000007A"
  badge-4k: "#42A5F5"
  badge-hdr: "#FFCA28"
  badge-dolby-vision: "#7A6A94"
  badge-atmos: "#FFD54F"
typography:
  display:
    fontFamily: "Be Vietnam Pro, Noto Sans SC, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Be Vietnam Pro, Noto Sans SC, sans-serif"
    fontSize: "24px"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "-0.01em"
  title:
    fontFamily: "Be Vietnam Pro, Noto Sans SC, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.4
    letterSpacing: "-0.01em"
  body:
    fontFamily: "Be Vietnam Pro, Noto Sans SC, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.43
    letterSpacing: "0.018em"
  label:
    fontFamily: "Be Vietnam Pro, Noto Sans SC, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.33
    letterSpacing: "0.04em"
rounded:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "32px"
  tv-safe: "48px"
components:
  button-primary:
    backgroundColor: "{colors.accent-cinema-gold-deep}"
    textColor: "{colors.ink-primary-light}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
  button-primary-hover:
    backgroundColor: "{colors.accent-cinema-gold}"
    textColor: "{colors.ink-primary-light}"
    rounded: "{rounded.sm}"
    padding: "12px 20px"
  card-surface:
    backgroundColor: "{colors.surface-raised}"
    textColor: "{colors.ink-primary}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  media-poster:
    backgroundColor: "{colors.surface-container}"
    rounded: "{rounded.md}"
    padding: "0"
---

# Design System: Medio Community

## Overview

**Creative North Star: "私人影院"**

Medio Community 的视觉系统服务于自托管流媒体工作流：暗色画布让海报与播放画面成为绝对主角，界面 chrome 退居幕后。默认深色模式（`#131315` 画布）营造晚间客厅观影的沉静感；强调色由用户可选（默认琥珀影院金），但中性层与排版保持稳定，不因换色而漂移。

系统拒绝廉价安卓视频 App 的高饱和堆叠、粗描边角标和渐变按钮；也拒绝 SaaS 灰白卡片与 AI 流媒体模板的编号段落脚手架。精致感来自克制的 tonal 分层、精准的 8pt 间距、以及有目的的动效，而非装饰性阴影或玻璃拟态。

**Key Characteristics:**

- 暗色画布 + 内容优先：海报、剧照、播放器画面占视觉权重 70% 以上
- 中性层固定、强调色可换：`AppNeutralScheme` 不随主题变体漂移
- 扁平 tonal 分层为主，阴影仅用于浮层响应态
- Material 3 组件基座 + 媒体专用语义色（播放绿、规格徽章、进度条）
- 三端统一令牌，交互按鼠标 / 触控 / D-Pad 分流

## Colors

暗色沉浸基调，强调色克制点缀；影院绿专用于播放动作，与主题 accent 分离。

### Primary

- **Cinema Gold（影院金）** (`#FFDCA1` / `#FFB800`): 默认暗色主题强调色（`AppThemeVariant.amber`）。用于选中态、chip 高亮、焦点环辅助，不超过单屏 10% 面积。
- **Accent Variants（可选强调色）**: 靛蓝、青绿、玫红等 8 种用户可选变体，仅替换 `ColorScheme.primary` 系列，不改变中性画布。

### Neutral

- **Obsidian Canvas（黑曜画布）** (`#131315`): 暗色 `scaffoldBackgroundColor`，主浏览背景。
- **Warm Ink（暖墨文字）** (`#E5E1E4`): 暗色主文字 `onSurface`。
- **Muted Silver（银灰元信息）** (`#9898A2`): 次级文字 `onSurfaceVariant`，年份、时长、辅助说明。
- **Raised Surface（抬升表面）** (`#2A2A2C`): `surfaceContainerHigh`，卡片、列表项、设置分组底。
- **Deep Well（深坑底）** (`#0E0E10`): `surfaceContainerLowest`，播放器沉浸区、全屏遮罩下缘。

### Semantic (AppColors)

- **Cinema Green（影院绿）** (`#43A047`): `playAction` / `progressActive`，海报播放按钮与续播进度，不随 accent 变体改变。
- **Spec Badges（规格徽章）**: 4K `#42A5F5`、HDR `#FFCA28`、Dolby Vision `#7A6A94`、Atmos `#FFD54F`，对齐主流播放器约定。
- **Scrim（遮罩）**: 海报悬停 / 控制栏背景，暗色 alpha 0.48–0.72。

### Named Rules

**The Content Canvas Rule.** 任何单屏界面，海报或视频画面应占据视觉焦点；accent 色与装饰元素合计不超过可见面积的 10%。

**The Fixed Neutral Rule.** 用户切换主题变体时，仅 accent 层变化；`#131315` 画布与表面 tonal 阶梯保持不动，避免「换色即换气质」。

## Typography

**Display Font:** Be Vietnam Pro（拉丁文主字体）
**Body Font:** Be Vietnam Pro + Noto Sans SC（中文回退）
**Label Font:** 同族，通过字重与字距区分

**Character:** 现代 grotesque 拉丁文搭配克制中文黑体，标题略紧（-0.02em），元信息疏朗可读。媒体卡标题 14px/600，区块标题 20px/600，避免超大 display 压过海报。

### Hierarchy

- **Display** (700, 32px, 1.25): 详情页片名、空态主标题；TV 端详情 hero。
- **Headline** (600, 24px, 1.33): 页面级标题、设置分组。
- **Title** (600, 20px, 1.4): 区块标题（「最近播放」「相关影视」），`AppTypography.sectionTitle`。
- **Body** (400, 14–16px, 1.43–1.5): 设置说明、列表副文案；行长建议 ≤65 字符等价宽度。
- **Label** (600, 10–12px, 0.04em tracking): 徽章（4K/HDR）、导航 pill、按钮标签。

### Named Rules

**The Poster First Rule.** 片名在卡片上不超过 14px/600 两行；详情页 display 不超过 32px，绝不用 hero 级 96px+ 标题压过海报。

## Elevation

本系统以 **tonal 分层** 传达深度，默认无投影。`AppElevation.level0` 为卡片与 AppBar 常态；仅 BottomSheet、Dialog、菜单使用 level3–4（6–8dp）。`surfaceTint` 强制透明，禁止 M3 默认 tint 污染表面色。

### Shadow Vocabulary

- **Flat Surface** (`elevation: 0`): 卡片、海报、列表项、导航栏。
- **Floating Layer** (`elevation: 6–8`): BottomSheet、Dialog、弹出菜单。
- **Focus Lift** (transform scale 1.04–1.08): TV/桌面海报聚焦时以缩放替代阴影，见 `TvFocusRing` / `_PosterFocusScale`。

### Named Rules

**The Flat-By-Default Rule.** 静止态禁止宽模糊阴影（blur ≥16px）与 1px 描边叠加；深度靠 `surfaceContainer` 阶梯色差表达。

## Components

组件气质：**精致克制、触感明确**。圆角封顶 16px（卡片），pill 仅用于 chip 与标签栏。

### Buttons

- **Shape:** 小圆角 8px（`AppRadius.sm`），非 pill。
- **Primary (Filled):** `primary` 背景 + `onPrimary` 文字；水平 20px / 垂直 12px 内边距；`labelLarge` 600。
- **Hover / Focus:** 8–12% `onPrimary` overlay；200ms `easeOutCubic`；TV 端加 `TvFocusRing` 外环。
- **Text / Outlined:** ghost 用于次要操作；描边 `outlineVariant`，禁止渐变填充。

### Chips

- **Style:** `surfaceContainerHighest` 底 + `outlineVariant` 细描边；选中态 `primaryContainer`。
- **Shape:** pill（`AppRadius.pill`）；标签 13px/500。

### Cards / Containers

- **Corner Style:** 12px（`AppRadius.md`），海报与媒体卡统一。
- **Background:** `surfaceContainerHighest` 或透明（海报卡无底色，仅图片 + 渐变 scrim）。
- **Shadow Strategy:** 无；悬停 / 聚焦用 scale + scrim。
- **Border:** 无装饰描边；分隔用 `outlineVariant` 0.5px divider。
- **Internal Padding:** 12–16px（`AppSpacing.md`–`lg`）。

### Inputs / Fields

- **Style:** M3 默认 + 8px 圆角；底 `surfaceContainerLow`。
- **Focus:** primary 色环或边框偏移；错误态 `danger` 语义色。
- **TV:** 设置页使用 `TvFocusListTile` / `TvFocusSlider`，最小触控 48dp。

### Navigation

- **Desktop:** 左侧栏 `home_pc_sidebar`，选中项 accent 指示 + `navLabel` 700。
- **Mobile:** 底部导航 / 抽屉，图标 + 14px 标签。
- **TV:** `tv_home_shell` 侧栏 + 内容区；D-Pad 焦点遍历，`TvScreenShell` 统一安全区 48dp。

### Media Poster Card（签名组件）

- 2:3 海报比例；圆角 12px；底部 scrim 渐变 + 片名 `cardTitle` 14px/600。
- 悬停 / 聚焦：scale 1.04–1.08，200ms；播放按钮 `playAction` 影院绿圆形。
- 角标：`badge` 10px/700 白字 on 规格色底，左上 / 右上不堆叠超过 2 个。

## Do's and Don'ts

### Do:

- **Do** 默认暗色画布 `#131315`，让海报色彩成为界面最饱和的元素。
- **Do** 用 `AppSpacing` 8pt 体系（4/8/12/16/24/32/48）保持三端节奏一致。
- **Do** 播放相关操作用影院绿 `#43A047`，与主题 accent 分离，建立播放信任感。
- **Do** TV 端所有可交互元素接入焦点环与 `minTouchTarget` 48dp。
- **Do** 动效使用 `AppMotion` 令牌（80–350ms，`easeOutCubic`），并尊重 `prefers-reduced-motion`。

### Don't:

- **Don't** 使用廉价安卓视频 App 风：高饱和渐变按钮、粗描边角标、杂乱多色图标堆叠。
- **Don't** 使用 SaaS 后台风：灰白卡片 + 大圆角（>16px）+ 宽模糊阴影与 1px 描边叠加。
- **Don't** 在浏览页堆砌促销标签、弹窗、广告位，挤占海报网格。
- **Don't** 每节加小写全大写 eyebrow 或 `01 / 02 / 03` 编号脚手架。
- **Don't** 用渐变文字（`background-clip: text`）或装饰性玻璃拟态卡片。
- **Don't** 将内容可见性绑定在入场动画上；减少动态效果下内容必须立即可见。
