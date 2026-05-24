import 'package:flutter/material.dart';
import '../game_controller.dart';
import '../../models/conveyor.dart';
import '../../models/special_type.dart';

/// Implement this to add a new special box type without touching core game code.
/// Register with [SpecialRegistry.register] before [GameController.startGame].
///
/// Example — new "lightning" type that clears ALL belts:
///   class LightningEffect implements SpecialEffect { ... }
///   SpecialRegistry.register(LightningEffect());
abstract class SpecialEffect {
  SpecialType get type;

  /// Called when a special box of [type] reaches its gate.
  /// Use [ctrl]'s public API: addScore, addPopup, conveyors, etc.
  void onScore(GameController ctrl, Conveyor conv, bool isDown,
      double gateY, double popupY);

  /// Emoji / text shown in the combo-area reward slot when no image asset exists.
  String get fallbackIcon;

  /// Color used for the incoming popup.
  Color get popupColor => const Color(0xFFFF6600);

  /// Label shown when the combo completes and this reward is about to spawn.
  String get incomingLabel => '${fallbackIcon} INCOMING!';
}

/// Static registry — entries survive the lifetime of the process.
/// Register your custom effects at app startup.
class SpecialRegistry {
  SpecialRegistry._();

  static final _map = <SpecialType, SpecialEffect>{};

  static void register(SpecialEffect e) => _map[e.type] = e;
  static SpecialEffect? find(SpecialType t) => _map[t];
  static Iterable<SpecialEffect> get all => _map.values;
  static void clear() => _map.clear();
}
