import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// Holds the translated strings needed by canvas painters (no BuildContext).
/// Call [update] once per frame from GameScreen.build() so the painter
/// always reads the current locale.
class AppStrings {
  AppStrings._();

  // HUD labels
  static String scoreLbl = 'SCORE';
  static String levelLbl = 'LEVEL';
  static String livesLbl = 'LIVES';

  // In-game canvas labels
  static String bossHp = 'BOSS HP';
  static String combo  = 'COMBO';

  static void update(BuildContext context) {
    scoreLbl = context.tr('score');
    levelLbl = context.tr('level_lbl');
    livesLbl = context.tr('lives_lbl');
    bossHp   = context.tr('boss_hp');
    combo    = context.tr('combo');
  }
}
