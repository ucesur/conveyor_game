import 'box_color.dart';
import 'special_type.dart';

class ComboArea {
  final List<BoxColor> recipe;
  // Which special item gets spawned on a conveyor when this combo completes.
  final SpecialType reward;
  int progress;
  double? completionTime;

  ComboArea({required this.recipe, required this.reward}) : progress = 0;

  bool get isComplete => progress >= recipe.length;
  BoxColor? get currentTarget => isComplete ? null : recipe[progress];
}
