import '../../core/theme/app_radius.dart';

/// Stitch home screen layout tokens (`streaming-home-cinematic-clean-ui`).
abstract final class HomeLayout {
  static const horizontalMargin = 20.0;
  static const sectionGap = 32.0;
  static const sectionHeaderGap = 16.0;

  /// Tailwind `underline-offset-4` on recommend filter tabs.
  static const filterUnderlineOffset = 4.0;
  static const filterUnderlineThickness = 2.0;
  static const sectionInnerGap = 12.0;
  static const posterTitleGap = 8.0;
  static const gridGap = 16.0;
  static const cardPadding = 4.0;
  static const badgeInset = 8.0;
  static const searchBarHeight = 48.0;

  /// Search bar `mt-md` / `mb-md` before continue-watching.
  static const searchBarVerticalMargin = 16.0;

  /// Section title (`headline-lg-mobile`) & trailing link (`label-sm`).
  static const sectionTitleFontSize = 20.0;
  static const sectionTitleLineHeight = 28 / 20;
  static const sectionTitleLetterSpacing = -0.2;
  static const sectionLinkFontSize = 12.0;
  static const sectionLinkLineHeight = 16 / 12;
  static const featuredThumbFlex = 2;
  static const featuredBodyFlex = 3;

  /// Stitch `rounded-xl` = 0.75rem (12px) on poster / glass cards.
  static const posterRadius = AppRadius.md;
  static const posterRadiusR = AppRadius.mdR;

  static const cardRadius = posterRadius;
  static const cardRadiusR = posterRadiusR;

  /// `rounded-lg` — featured continue thumb (8px).
  static const thumbRadius = AppRadius.sm;
  static const thumbRadiusR = AppRadius.smR;

  /// `rounded-md` — secondary continue thumb (4px).
  static const smallThumbRadius = AppRadius.xs;
  static const smallThumbRadiusR = AppRadius.xsR;

  /// Stitch `body-md` / `label-sm` line metrics for poster captions.
  /// Recommend poster width:height = 2:3 (slimmer vertical rectangle; matches [MediaCard]).
  static const recommendPosterAspectRatio = 2 / 3;

  /// PC sidebar (`w-64`) and content shell.
  static const pcSidebarWidth = 256.0;
  static const pcSidebarPaddingTop = 32.0;
  static const pcSidebarNavInset = 12.0;
  static const pcSidebarBrandInset = 24.0;
  static const pcSidebarBrandGap = 32.0;
  static const pcSidebarNavGap = 8.0;
  static const pcSidebarNavPaddingH = 24.0;
  static const pcSidebarNavPaddingV = 12.0;
  static const pcSidebarIconSize = 24.0;
  static const pcSidebarIconGap = 16.0;
  static const pcContentMaxWidth = 1200.0;
  /// PC 顶栏搜索触发器宽度（约为内容区的 80%，对齐续播/推荐左缘节奏）。
  static const pcSearchMaxWidth = 960.0;
  static const pcRecommendColumns = 5;
  static const pcHeroAspectRatio = 21 / 9;
  static const pcSectionGap = 24.0;
  static const pcSectionTitleFontSize = 24.0;
  static const pcSectionTitleLineHeight = 32 / 24;
  /// Hero title — scaled down from Stitch `display-lg` for typical desktop DPI.
  static const pcHeroTitleFontSize = 28.0;
  static const pcHeroTitleLineHeight = 36 / 28;
  /// Stitch `p-xl` on hero overlay content.
  static const pcHeroContentPadding = 32.0;
  /// Stitch `p-lg` on secondary continue cards.
  static const pcSecondaryContentPadding = 24.0;
  static const pcHeroBadgeTitleGap = 8.0;
  static const pcHeroTitleMetaGap = 4.0;
  static const pcHeroMetaProgressGap = 16.0;
  static const pcHeroProgressButtonGap = 24.0;
  static const pcSecondaryTitleMetaGap = 4.0;
  static const pcSecondaryMetaProgressGap = 12.0;
  /// Stitch `max-w-md` progress track on hero card.
  static const pcHeroProgressMaxWidth = 448.0;
  static const pcProgressBarHeight = 4.0;
  static const pcHeroImageOpacity = 0.8;
  static const pcSecondaryImageOpacity = 0.7;
  static const pcSecondaryUniformDarken = 0.18;
  static const pcHeroUniformDarken = 0.08;
  static const pcRecommendImageOpacity = 0.8;
  static const pcRecommendUniformDarken = 0.06;
  /// Stitch `top-3` badge inset on recommend posters.
  static const pcRecommendBadgeInset = 12.0;
  /// Stitch `p-sm` footer on recommend posters.
  static const pcRecommendFooterPadding = 12.0;
  /// Stitch `bottom-sm` / `right-sm` on recommend play button.
  static const pcRecommendPlayButtonInset = 8.0;
  static const pcRecommendPlayButtonSize = 40.0;
  /// Stitch `translate-y-2` footer lift before hover.
  static const pcRecommendFooterHoverOffset = 8.0;
  static const pcRecommendImageHoverScale = 1.05;
  static const pcHeroMetaFontSize = 14.0;
  /// Stitch `px-8 py-3` hero action pills.
  static const pcActionButtonHPad = 32.0;
  static const pcActionButtonVPad = 12.0;
  static const pcActionButtonGap = 16.0;
  static const pcActionButtonFontSize = 12.0;
  static const pcHeroPlayIconSize = 24.0;
  static const pcHeroPlayIconGap = 8.0;

  static const posterTitleFontSize = 14.0;
  static const posterTitleLineHeight = 20 / 14;
  static const posterSubtitleFontSize = 12.0;
  static const posterSubtitleLineHeight = 16 / 12;

  /// Caption block below recommend posters (title + subtitle + gap).
  static double get recommendCaptionHeight =>
      posterTitleGap +
      posterTitleFontSize * posterTitleLineHeight +
      posterSubtitleFontSize * posterSubtitleLineHeight;

  /// Grid cell height for [HomeRecommendCard] tiles (matches homepage recommend section).
  static double recommendGridCellHeight(double tileWidth, {bool pcStyle = false}) {
    const layoutSlopPx = 2.0;
    final posterH = tileWidth / recommendPosterAspectRatio;
    if (pcStyle) return posterH + layoutSlopPx;
    return posterH + recommendCaptionHeight + layoutSlopPx;
  }
}
