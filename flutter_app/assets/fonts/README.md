# Legacy icon font

`LegacySymbols.ttf` is the static, weight-400 Material Symbols Outlined font used by `Legacy/Pages/Shared/_Layout.cshtml`, downloaded from Google's font stylesheet on 2026-09-07. The font is bundled so all targets render the same icons offline.

Source stylesheet: https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined
Codepoint names: https://github.com/google/material-design-icons/tree/master/variablefont
License: Apache 2.0, reproduced in `LICENSE.txt` and registered with Flutter's license registry.

The UI uses this font for icons only; it does not use Material navigation or button styling. `lib/legacy_icons.dart` retains upstream symbol names to make comparisons with Legacy's HTML straightforward.
