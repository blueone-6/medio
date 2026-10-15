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
  xl: "20px"
  xxl: "28px"
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

> 版本 v1.1 · 最后更新 2026-10-15 · 令牌以 Dart 常量层为唯一事实来源（见「Token → Code 映射」）。

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
- **Accent Variants（可选强调色）**: 8 种用户可选变体（靛蓝、青绿、玫红等），仅替换 `ColorScheme.primary` / `primaryContainer` 系列，不改变中性画布。变体总表见 `AppAccentPalette`。
  - **On-accent rule**: 变体切换时，`primary` 上的文字必须走 `onPrimary`，不得硬编码白/黑 —— 浅色变体（如琥珀）配深墨字、深色变体配白字。

### Neutral

- **Obsidian Canvas（黑曜画布）** (`#131315`): 暗色 `scaffoldBackgroundColor`，主浏览背景。
- **Warm Ink（暖墨文字）** (`#E5E1E4`): 暗色主文字 `onSurface`。
- **Muted Silver（银灰元信息）** (`#9898A2`): 次级文字 `onSurfaceVariant`，年份、时长、辅助说明。
- **Raised Surface（抬升表面）** (`#2A2A2C`): `surfaceContainerHigh`，卡片、列表项、设置分组底。
- **Deep Well（深坑底）** (`#0E0E10`): `surfaceContainerLowest`，播放器沉浸区、全屏遮罩下缘。

### Semantic (AppColors)

- **Cinema Green（影院绿）** (`#43A047`): `playAction` / `progressActive`，海报播放按钮与续播进度，不随 accent 变体改变。
- **Spec Badges（规格徽章）**: 4K `#42A5F5`、HDR `#FFCA28`、Dolby Vision `#7A6A94`、Atmos `#FFD54F`，底色对齐主流播放器约定。
  - **Badge ink rule（重要）**: 徽章文字**不固定白色**。规格色跨越明度极大（HDR `#FFCA28` 白字仅 ≈1.5:1，Atmos `#FFD54F` ≈1.4:1，4K `#42A5F5` ≈2.6:1，均不达标；Dolby Vision 深紫白字 ≈4.9:1 合格）。规则：**逐徽章取白字/深墨字（`ink-primary-light`）中对比度更高者**，保证 10px 标签 ≥4.5:1。实现见 `media_badges.dart`。
- **Scrim（遮罩）**: 海报悬停 / 控制栏 / 图上文字背景。装饰遮罩 alpha 0.48–0.72；**承载文字的媒体 scrim 允许更高（0.80–0.92）**，以在任意海报上保证 ≥4.5:1（见 Accessibility）。

### Named Rules

**The Content Canvas Rule.** 任何单屏界面，海报或视频画面应占据视觉焦点；accent 色与装饰元素合计不超过可见面积的 10%。

**The Fixed Neutral Rule.** 用户切换主题变体时，仅 accent 层变化；`#131315` 画布与表面 tonal 阶梯保持不动，避免「换色即换气质」。

**The Over-Image Legibility Rule.** 任何压在媒体图（海报/剧照/backdrop）上的文字，必须由 scrim 保证对比度；禁止把白字直接放在无法控制的图片上「碰运气」。这是本系统历史线上缺陷最集中的一处。

## Typography

**Display Font:** Be Vietnam Pro（拉丁文主字体）
**Body Font:** Be Vietnam Pro + Noto Sans SC（中文回退）
**Label Font:** 同族，通过字重与字距区分

**Character:** 现代 grotesque 拉丁文搭配克制中文黑体，标题略紧（-0.02em），元信息疏朗可读。媒体卡标题 14px/600，区块标题 20px/600，避免超大 display 压过海报。

### Hierarchy

- **Display** (700, 32px, 1.25): 详情页片名、空态主标题；TV 端详情 hero。**上限 32px，禁止 hero 级 96px+ 标题压过海报。**
- **Headline** (600, 24px, 1.33): 页面级标题、设置分组。
- **Title** (600, 20px, 1.4): 区块标题（「最近观看」「相关影视」），`AppTypography.sectionTitle`。
- **Body** (400, 14–16px, 1.43–1.5): 设置说明、列表副文案。
- **Label** (600, 10–12px, 0.04em tracking): 徽章（4K/HDR）、导航 pill、按钮标签。

### Named Rules

**The Poster First Rule.** 片名在卡片上不超过 14px/600 两行；详情页 display 不超过 32px，绝不用 hero 级 96px+ 标题压过海报。

### Fine print

- **Row length（行长）.** 正文行长上限 ≈ **65 字符 / ≈45 个汉字**。桌面宽屏的简介正文需显式限宽（`kMediaDetailOverviewMaxWidth = 760`），不允许随容器拉成上百字一行。
- **CJK tracking.** frontmatter 的 `body.letterSpacing = 0.018em` 针对拉丁文；**中文正文建议 0 或负值**，正字距会让中文显松。实现按语言分别应用。
- **Tabular numerals.** 评分、进度（`162/200`）、时长、计时等数字必须用等宽数字（`FontFeature.tabularFigures`），否则网格与列表里数字宽度抖动。

## Spacing

8pt 体系，三端节奏统一（`AppSpacing` / `HomeLayout`）。间距用于表达「同组 / 不同组」，不要用间距当装饰。

| Token | 值 | 典型用途 |
|---|---|---|
| `xs` | 4px | 图标与文字、徽章内边距 |
| `sm` | 8px | 元素内部紧凑间隔、标题与元信息 |
| `md` | 12px | 卡片内边距、列表项内边距 |
| `lg` | 16px | 卡片内边距、组件间 |
| `xl` | 24px | 分组之间、区块标题与内容 |
| `xxl` | 32px | 页面区块之间 |
| `tv-safe` | 48px | TV 安全区边距 |

**货架节奏（Home）：** `sectionGap 40` / `sectionHeaderGap 20` / `gridGap 18`。区块之间留白要显著大于区块内部，避免海报网格糊成一片。

## Elevation

本系统以 **tonal 分层** 传达深度，默认无投影。`surfaceTint` 强制透明，禁止 M3 默认 tint 污染表面色。

| Token | dp | 用途 |
|---|---|---|
| `level0` | 0 | 卡片、海报、AppBar 常态 |
| `level1` | 1 | AppBar 抬升、卡片悬停 |
| `level2` | 3 | 卡片选中 / chip 抬升 |
| `level3` | 6 | 浮层 / 菜单 |
| `level4` | 8 | Dialog / BottomSheet |
| `level5` | 12 | FAB / 最高浮层 |

### Shadow Vocabulary

- **Flat Surface** (`elevation: 0`): 卡片、海报、列表项、导航栏。
- **Floating Layer** (`elevation: 6–8`): BottomSheet、Dialog、弹出菜单。
- **Focus Lift** (transform scale 1.04–1.08): TV/桌面海报聚焦时以缩放替代阴影，见 `TvFocusRing` / `PosterFocusScale`。

### Named Rules

**The Flat-By-Default Rule.** 静止态禁止宽模糊阴影（blur ≥16px）与 1px 描边叠加；深度靠 `surfaceContainer` 阶梯色差表达。悬停/聚焦用 **scale + scrim**，不用阴影。

## Motion

统一由 `AppMotion` 管理。**键盘高频操作（命令面板类）不做动画**；UI 动画原则上 ≤300ms。

### Duration

| Token | 值 | 用途 |
|---|---|---|
| `instant` | 80ms | 按下反馈、极短状态切换 |
| `fast` | 120ms | hover、颜色/小状态切换 |
| `base` | 200ms | 常规过渡、淡入淡出、进入 |
| `slow` | 300ms | 展开/收起、较明显过渡 |
| `page` | 350ms | 页面转场 |
| `shimmer` | 1200ms | 骨架屏 shimmer 循环（唯一的长时动效） |

### Curve

| Token | 曲线 | 用途 |
|---|---|---|
| `standard` | `easeInOutCubicEmphasized` | 进出、需要强调的运动 |
| `emphasized` | `easeOutCubic` | 主要动感 |
| `decelerate` | `easeOutCubic` | 元素进入屏幕（快起缓停） |
| `accelerate` | `easeInCubic` | 元素离开屏幕 |

### Named Rules

**The Motion Budget Rule.** 只动 `transform` / `opacity`；退出比进入快；不用外部弹性/回弹（会显廉价）。**reduced-motion 下时间归零但要保留状态可见**（`AppMotion.effectiveDuration` → `Duration.zero`，`AppMotion.animationsEnabled`）。

**The One Hero Moment Rule.** 每个页面最多一个招牌入场动效；不要对每个区块都套「滚动淡入上升」。

## Accessibility

三端所有界面必须满足（`PRODUCT.md` 的 Accessibility 目标的实现口径）：

| 项 | 要求 |
|---|---|
| 正文对比度 | ≥ 4.5:1（含占位符、次要有意义文字） |
| 大字号对比度 | ≥ 3:1（≥18px 或 ≥14px bold） |
| 非文本 / UI 组件 | ≥ 3:1（图标、进度条、滑块轨道、输入框边框、焦点指示） |
| 触控目标 | ≥ 48×48dp（TV/触控）；桌面鼠标命中可更小但有 hover 反馈 |
| 焦点可见 | 任何可聚焦元素必须有可见焦点指示（TV `TvFocusRing`；桌面对齐同规则） |
| 图上文字 | 必须由 scrim 保证对比（见 Over-Image Legibility Rule） |
| 动态效果 | 尊重 `prefers-reduced-motion` / `MediaQuery.disableAnimations`；关闭后内容必须立即可见 |
| 语义 | 图标按钮必须有 label；装饰图标 `ExcludeSemantics`；列表选中态用 `Semantics(selected:)` |

## Responsive & Breakpoints

三端共用令牌，按宽度与平台分流。**断点是推荐值，当前实现阈值见括号。**

| 级别 | 宽度 | 布局要点 |
|---|---|---|
| Compact（手机） | < 600 | 单列/两列网格；底部导航；媒体卡标题在图片下方 |
| Medium（平板/窄窗） | 600–899 | 两–三列；网格自适应列数 |
| Expanded（桌面） | ≥ 900（hero 宽态阈值）| 左侧栏 + 内容区；4 列海报；标题叠图上 |
| TV | 平台判定（`context.isTvUi`）| 48dp 安全区；D-Pad 焦点遍历；大卡两行 |

**Allowed only-in-document rule:** 桌面端主内容最大宽度 `pcContentMaxWidth = 1200`，超出后居中留白，不无限拉宽；海报网格单行不足时居中，不贴左。

## Iconography

- **集:** Material Symbols / `Icons.*`（Material）。不混入 emoji 当图标。
- **尺寸:** 16（行内）/ 20（按钮/列表）/ 24（导航/工具，`pcSidebarIconSize`）。选中态用 filled，未选中用 outlined（同一语义成对，如 `home_outlined` / `home`）。
- **颜色:** 继承 `onSurfaceVariant`；选中/激活用 `primary` 或 `onSurface`；不硬编码。
- **语义:** 纯装饰图标不进入无障碍树；图标按钮必须有 `label` / tooltip。

## Components

组件气质：**精致克制、触感明确**。圆角：卡片/海报 12–16px（`md`/`lg`），输入/按钮 8px（`sm`），chip 与标签栏用 pill。弹层/Sheet 可到 `xl 20` / `xxl 28`。

### Buttons

- **Shape:** 常规按钮小圆角 8px（`AppRadius.sm`），非 pill。
- **Hero Action Pill（明确例外）:** 首页/详情 hero 上的主次行为药丸（播放 / 详情）使用 **pill**（延续 Stitch hero 形态），仅限 hero 大图上的动作区。
- **Primary (Filled):** `primary` 背景 + `onPrimary` 文字；水平 20px / 垂直 12px 内边距；`labelLarge` 600。
- **Hover / Focus:** 8–12% `onPrimary` overlay；200ms `emphasized`；TV 端加 `TvFocusRing` 外环。
- **Text / Outlined:** ghost 用于次要操作；描边 `outlineVariant`，禁止渐变填充。

### Chips

- **Style:** `surfaceContainerHighest` 底 + `outlineVariant` 细描边；选中态 `primaryContainer`。
- **Shape:** pill（`AppRadius.pill`）；标签 13px/500。

### Cards / Containers

- **Corner Style:** 12px（`AppRadius.md`），海报与媒体卡统一。
- **Background:** `surfaceContainerHighest` 或透明（海报卡无底色，仅图片 + 渐变 scrim）。
- **Shadow Strategy:** 无；悬停 / 聚焦用 scale + scrim。
- **Border:** 分隔用 `outlineVariant`）。媒体卡可用固定中性 rim（`mediaRimSolidDark #3E3E46`）。
- **Internal Padding:** 12–16px（`AppSpacing.md`–`lg`）。

### Inputs / Fields

- **Style:** M3 默认 + 8px 圆角；底 `surfaceContainerLow`。
- **Focus:** primary 色环或边框偏移；错误态 `danger` 语义色。
- **TV:** 设置页使用 `TvFocusListTile` / `TvFocusSlider`，最小触控 48dp。

### Sliders

- **Track:** active = `primary`；**inactive = `onSurfaceVariant`**（不用 `surfaceContainerHighest`，其在设置卡片上仅 ≈1.4:1）。高亮进度条（海报/hero 上）加 1px 深色描边以保证压在图片上仍 ≥3:1。

### Navigation

- **Desktop:** 左侧栏 `home_pc_sidebar`，选中项 accent 指示 + `navLabel` 700。
- **Mobile:** 底部导航 / 抽屉，图标 + 14px 标签。
- **TV:** `tv_home_shell` 侧栏 + 内容区；D-Pad 焦点遍历，`TvScreenShell` 统一安全区 48dp。

### Media Poster Card（签名组件）

- 2:3 海报比例；圆角 12px；底部 scrim 渐变 + 片名 `cardTitle` 14px/600。
- 悬停 / 聚焦：**整卡抬升 + scale 1.04–1.08** + 图片内缩放，200ms `decelerate`；不加阴影。
- 播放按钮 `playAction` 影院绿。
- 角标：`badge` 10px/700，**底色为规格色时文字逐色取高对比前景**（见 Badge ink rule），左上/右上不堆叠超过 2 个。

### State matrix（所有可交互组件）

| 态 | 视觉 | 备注 |
|---|---|---|
| default | 基础色令牌 | — |
| hover | 5–8% overlay / scale | 仅指针设备；触控不加 hover |
| focus | `primary` 焦点环/描边，≥3:1 | 键盘/D-Pad 必须可见 |
| pressed | overlay 12% + 轻缩放 | 按下即反馈（不等抬手） |
| selected | `primaryContainer` + accent 文字 | 用 `Semantics(selected:)` |
| disabled | `onSurface` 38% / 无交互 | 不可聚焦 |
| loading | `Skeleton` / 进度 | 保留布局空间，避免跳动 |
| error | `danger` 语义色 + 可重试 | 文案指出下一步 |

## Content & Voice

- **语气:** 直接、具体、安抚。影院级专业感，不喊口号。
- **标签命名:** 用内容名而非泛称（「最近入库」而非「内容」）；导航项对应其内容。
- **错误/空态:** 说清「发生了什么 + 下一步怎么做」（如空态给「刷新」动作），不出现原始技术枚举（`CollectionFolder` 之类不得直接展示）。
- **按钮动词:** 用具体动作（播放 / 重试 / 详情），不用「确定/取消」式空话。

## Token → Code 映射（防漂移）

| Token | Dart 常量 |
|---|---|
| 中性色阶 | `AppNeutralScheme`（`app_neutral_scheme.dart`） |
| 强调色 / 变体 | `AppAccentPalette`（`app_accent_palette.dart`） |
| 语义色（播放绿/进度/徽章） | `AppColors`（`app_colors.dart`） |
| 圆角 | `AppRadius`（`app_radius.dart`：xs4/sm8/md12/lg16/xl20/xxl28/pill999） |
| 间距 | `AppSpacing`、`HomeLayout` |
| 高度 | `AppElevation`（0/1/3/6/8/12） |
| 动效 | `AppMotion`（时长/曲线/reduced-motion） |
| 排版 | `AppTypography` + `AppTextStyles` |
| 媒体 scrim | `homeMediaBackdropScrim`（`glass_surface.dart`） |
| 玻璃/rim 令牌 | `HomeGlassTokens`（`glass_surface.dart`） |
| 焦点环 / 海报聚焦缩放 | `TvFocusRing`、`PosterFocusScale` |

## Do's and Don'ts

### Do:

- **Do** 默认暗色画布 `#131315`，让海报色彩成为界面最饱和的元素。
- **Do** 用 `AppSpacing` 8pt 体系（4/8/12/16/24/32/48）保持三端节奏一致。
- **Do** 播放相关操作用影院绿 `#43A047`，与主题 accent 分离，建立播放信任感。
- **Do** TV 端所有可交互元素接入焦点环与 `minTouchTarget` 48dp。
- **Do** 动效使用 `AppMotion` 令牌（80–350ms；shimmer 1200ms），并尊重 `prefers-reduced-motion`。
- **Do** 图上文字一律落在 scrim 上；规格徽章文字逐色取高对比前景。
- **Do** 数字（评分/进度/时长）用等宽数字，保证对齐不抖。

### Don't:

- **Don't** 使用廉价安卓视频 App 风：高饱和渐变按钮、粗描边角标、杂乱多色图标堆叠。
- **Don't** 使用 SaaS 后台风：灰白卡片 + 大圆角（>16px 用于卡片）+ 宽模糊阴影与 1px 描边叠加。
- **Don't** 在浏览页堆砌促销标签、弹窗、广告位，挤占海报网格。
- **Don't** 每节加小写全大写 eyebrow 或 `01 / 02 / 03` 编号脚手架。
- **Don't** 用渐变文字（`background-clip: text`）或装饰性玻璃拟态卡片。
- **Don't** 将内容可见性绑定在入场动画上；减少动态效果下内容必须立即可见。
- **Don't** 直接展示原始技术枚举（`CollectionFolder`、`Mixed content` 之类）作为用户可见标签。
