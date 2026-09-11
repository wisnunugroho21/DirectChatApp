import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';
import 'legacy_icons.dart';

/// A keyboard-accessible HTML-style button, without ink or Material elevation.
class LegacyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? background, foreground;
  final Color? hoverBackground;
  final double radius;
  final EdgeInsets padding;
  final double? width, height;
  final Border? border;
  const LegacyButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.background,
    this.foreground,
    this.hoverBackground,
    this.radius = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    this.width,
    this.height,
    this.border,
  });
  @override
  State<LegacyButton> createState() => _LegacyButtonState();
}

class _LegacyButtonState extends State<LegacyButton> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final active = enabled && (hovered || focused);
    final foreground =
        widget.foreground ??
        (widget.background == null ? LegacyStyle.muted : Colors.white);
    Widget result = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => hovered = v),
        onShowFocusHighlight: (v) => setState(() => focused = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: enabled ? 1 : .4,
            child: Container(
              width: widget.width,
              height: widget.height,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: active
                    ? (widget.background == null
                          ? widget.hoverBackground ?? LegacyStyle.soft
                          : widget.background == LegacyStyle.accent
                          ? LegacyStyle.accentDark
                          : widget.background)
                    : widget.background,
                borderRadius: BorderRadius.circular(widget.radius),
                boxShadow: widget.background == LegacyStyle.accent
                    ? const [
                        BoxShadow(
                          color: Color(0x352563eb),
                          blurRadius: 18,
                          offset: Offset(0, 7),
                        ),
                      ]
                    : null,
                border: focused
                    ? Border.all(color: const Color(0xff93c5fd), width: 2)
                    : widget.border,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: foreground,
                  fontSize: 13.5,
                  fontWeight: widget.background == LegacyStyle.accent
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground, size: 24),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        excludeFromSemantics: true,
        child: result,
      );
    }
    return result;
  }
}

class LegacyIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool primary;
  final Color? background, foreground;
  final double size, radius;
  const LegacyIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
    this.background,
    this.foreground,
    this.size = 42,
    this.radius = 13,
  });
  @override
  Widget build(BuildContext context) => LegacyButton(
    onPressed: onPressed,
    tooltip: tooltip,
    width: size,
    height: size,
    radius: radius,
    padding: EdgeInsets.zero,
    background: background ?? (primary ? LegacyStyle.accent : null),
    foreground: foreground,
    child: Icon(icon),
  );
}

class LegacyMenu extends StatelessWidget {
  final String tooltip;
  final List<({String label, VoidCallback action})> items;
  const LegacyMenu({super.key, required this.tooltip, required this.items});
  @override
  Widget build(BuildContext context) => Builder(
    builder: (buttonContext) => LegacyIconButton(
      icon: LegacyIcons.more_vert,
      tooltip: tooltip,
      onPressed: () {
        final box = buttonContext.findRenderObject()! as RenderBox;
        final point = box.localToGlobal(Offset.zero);
        showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Close menu',
          barrierColor: Colors.transparent,
          transitionDuration: const Duration(milliseconds: 120),
          pageBuilder: (context, _, _) {
            final size = MediaQuery.sizeOf(context);
            return Stack(
              children: [
                Positioned(
                  top: math.min(
                    point.dy + 46,
                    size.height - items.length * 44 - 24,
                  ),
                  left: (point.dx - 180).clamp(
                    8,
                    math.max(8, size.width - 236),
                  ),
                  width: 228,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: LegacyStyle.border),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x301e3a5f),
                          blurRadius: 42,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final item in items)
                          LegacyButton(
                            radius: 10,
                            foreground: LegacyStyle.text,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              item.action();
                            },
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(item.label),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  final String name;
  final String? initials;
  final String? colorKey;
  final bool profile;
  final bool group;
  final int? memberCount;
  final double radius;
  final bool? online;
  const ProfileAvatar({
    super.key,
    required this.name,
    this.initials,
    this.colorKey,
    this.profile = false,
    this.group = false,
    this.memberCount,
    this.radius = 24.5,
    this.online,
  });
  @override
  Widget build(BuildContext context) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length > 1
        ? '${parts.first.characters.first}${parts[1].characters.first}'
        : parts.first.characters.take(2).toString();
    const palette = [
      [Color(0xff2563eb), Color(0xff60a5fa)],
      [Color(0xff1d4ed8), Color(0xff3b82f6)],
      [Color(0xff0369a1), Color(0xff38bdf8)],
      [Color(0xff4338ca), Color(0xff818cf8)],
      [Color(0xff0284c7), Color(0xff7dd3fc)],
      [Color(0xff1e40af), Color(0xff93c5fd)],
    ];
    final hash = (colorKey ?? '').codeUnits.fold<int>(
      0,
      (hash, code) => (hash * 31 + code) & 0xffffffff,
    );
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: profile
                  ? Border.all(color: Colors.white, width: 3)
                  : null,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: group
                    ? const [Color(0xff7c3aed), Color(0xff4f46e5)]
                    : palette[profile ? 0 : hash % palette.length],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x20173a65),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: group
                ? Icon(LegacyIcons.groups, color: Colors.white, size: radius)
                : Text(
                    (this.initials ?? initials).toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: profile ? 14 : radius * .69,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                    ),
                  ),
          ),
          if (group && memberCount != null)
            Positioned(
              right: -4,
              bottom: -3,
              child: Container(
                height: 20,
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xff4f46e5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: LegacyStyle.sidebar, width: 2),
                ),
                child: Text(
                  '$memberCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          if (!group && online != null)
            Positioned(
              right: 0,
              bottom: 1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online!
                      ? LegacyStyle.success
                      : const Color(0xffa8b6c5),
                  border: Border.all(color: LegacyStyle.sidebar, width: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 52),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: LegacyStyle.soft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 28, color: LegacyStyle.accent),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250),
          child: Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: LegacyStyle.muted,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}

/// Bootstrap's auth container/column widths from the two legacy Razor pages.
class AuthLayout extends StatelessWidget {
  final Widget child;
  final bool register;
  const AuthLayout({super.key, required this.child, this.register = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff8f9fa),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width = bounds.maxWidth;
          final container = width >= 1400
              ? 1320.0
              : width >= 1200
              ? 1140.0
              : width >= 992
              ? 960.0
              : width >= 768
              ? 720.0
              : width >= 576
              ? 540.0
              : width;
          final fraction = width >= 992
              ? (register ? 5 / 12 : 4 / 12)
              : width >= 768
              ? (register ? 7 / 12 : 6 / 12)
              : width >= 576
              ? 10 / 12
              : 1.0;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bounds.maxHeight),
              child: Center(
                child: SizedBox(
                  width: container * fraction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        fontFamily: 'Segoe UI',
                        fontFamilyFallback: ['Arial'],
                        fontSize: 16,
                        height: 1.5,
                        color: Color(0xff212529),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x13000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: child,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            register
                                ? '© 2026 ChatApp'
                                : '© 2026 Your Application',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xff6c757d),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class LegacyChatBackground extends StatelessWidget {
  final Widget child;
  const LegacyChatBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xfff3f8ff), Color(0xffeaf2fb)],
      ),
    ),
    child: CustomPaint(painter: _WallpaperPainter(), child: child),
  );
}

class _WallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final glowCenter = Offset(size.width * .88, size.height * .04);
    final glowRadius =
        math.sqrt(
          math.pow(size.width * .88, 2) + math.pow(size.height * .96, 2),
        ) *
        .28;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0xffdbeafe), Color(0x00dbeafe)],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );
    final paint = Paint()
      ..color = const Color(0x0c2563eb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (double y = 0; y < size.height; y += 260) {
      for (double x = 0; x < size.width; x += 260) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawCircle(const Offset(34, 40), 11, paint);
        canvas.drawCircle(const Offset(158, 108), 9, paint);
        canvas.drawCircle(const Offset(70, 232), 8, paint);
        final path = Path()
          ..moveTo(96, 28)
          ..relativeLineTo(13, 13)
          ..relativeLineTo(-13, 13)
          ..relativeLineTo(-13, -13)
          ..close()
          ..moveTo(150, 34)
          ..lineTo(176, 34)
          ..moveTo(150, 44)
          ..lineTo(168, 44)
          ..moveTo(212, 26)
          ..cubicTo(220, 26, 224, 32, 224, 38)
          ..cubicTo(224, 44, 218, 50, 210, 50)
          ..lineTo(206, 50)
          ..lineTo(198, 57)
          ..lineTo(198, 50)
          ..cubicTo(194, 48, 192, 44, 192, 38)
          ..cubicTo(192, 32, 198, 26, 212, 26)
          ..moveTo(28, 104)
          ..cubicTo(34, 96, 44, 96, 50, 104)
          ..moveTo(24, 118)
          ..lineTo(58, 118)
          ..moveTo(92, 96)
          ..lineTo(102, 118)
          ..lineTo(80, 110)
          ..close()
          ..moveTo(150, 124)
          ..lineTo(168, 124)
          ..moveTo(206, 100)
          ..lineTo(206, 122)
          ..moveTo(198, 110)
          ..lineTo(216, 110)
          ..moveTo(34, 178)
          ..lineTo(58, 178)
          ..lineTo(58, 196)
          ..lineTo(42, 196)
          ..lineTo(34, 203)
          ..close()
          ..moveTo(104, 172)
          ..cubicTo(112, 166, 120, 174, 114, 182)
          ..lineTo(102, 196)
          ..lineTo(90, 182)
          ..cubicTo(84, 174, 96, 166, 104, 172)
          ..moveTo(152, 186)
          ..lineTo(176, 186)
          ..moveTo(164, 176)
          ..lineTo(164, 196)
          ..moveTo(204, 172)
          ..lineTo(218, 180)
          ..lineTo(204, 188)
          ..close()
          ..addRect(const Rect.fromLTWH(120, 226, 30, 16))
          ..moveTo(188, 224)
          ..lineTo(188, 244)
          ..moveTo(182, 244)
          ..lineTo(196, 244);
        canvas.drawPath(path, paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter oldDelegate) => false;
}

class LegacyWelcome extends StatelessWidget {
  final VoidCallback onNewChat;
  const LegacyWelcome({super.key, required this.onNewChat});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final narrow = MediaQuery.sizeOf(context).width <= 420;
      final visualSize = narrow ? 108.0 : 132.0;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: bounds.maxHeight),
          child: Center(
            child: Container(
              width: 560,
              padding: EdgeInsets.symmetric(
                horizontal: narrow ? 12 : 32,
                vertical: narrow ? 28 : 42,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: visualSize,
                    height: visualSize,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          left: -48,
                          right: -48,
                          top: -48,
                          bottom: -48,
                          child: CustomPaint(painter: _WelcomeRings()),
                        ),
                        Transform.rotate(
                          angle: -math.pi / 45,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Colors.white, Color(0xffe6f0ff)],
                              ),
                              border: Border.all(
                                color: const Color(0xffcfe0f8),
                              ),
                              borderRadius: BorderRadius.circular(
                                narrow ? 32 : 38,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x24204e85),
                                  blurRadius: 60,
                                  offset: Offset(0, 22),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                LegacyIcons.local_shipping,
                                size: 24,
                                color: LegacyStyle.accent,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -9,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xff0f766e),
                              border: Border.all(
                                color: const Color(0xffeff6ff),
                                width: 4,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x350f766e),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              LegacyIcons.chat,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: narrow ? 42 : 50),
                  const Text(
                    'TMS CONNECT',
                    style: TextStyle(
                      color: LegacyStyle.accent,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.76,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Keep every trip connected',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: (MediaQuery.sizeOf(context).width * .04).clamp(
                        27,
                        38,
                      ),
                      height: 1.15,
                      letterSpacing: -1.33,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 470),
                    child: Text(
                      'Message dispatchers and drivers, share documents, and start secure calls from one place.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.65,
                        color: LegacyStyle.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  LegacyButton(
                    onPressed: onNewChat,
                    background: LegacyStyle.accent,
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LegacyIcons.add_comment, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Start a conversation',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LegacyIcons.lock,
                        size: 15,
                        color: Color(0xff0f766e),
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Private and secure communication',
                          style: TextStyle(
                            color: Color(0xff7890a8),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _WelcomeRings extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x75cfe0f8);
    canvas.drawCircle(center, size.width / 2 - 23, paint);
    paint.color = const Color(0x5cbfd4f3);
    final rect = Offset.zero & size;
    for (var a = 0.0; a < math.pi * 2; a += .07) {
      canvas.drawArc(rect, a, .035, false, paint);
    }
  }

  @override
  bool shouldRepaint(_WelcomeRings oldDelegate) => false;
}

class LegacyBubbleTail extends CustomPainter {
  final bool mine, first;
  const LegacyBubbleTail({required this.mine, required this.first});
  @override
  void paint(Canvas canvas, Size size) {
    if (!first) return;
    final path = Path();
    if (mine) {
      path.moveTo(size.width - 5, 0);
      path.lineTo(size.width + 7, 0);
      path.lineTo(size.width - 1, 8);
    } else {
      path.moveTo(5, 0);
      path.lineTo(-7, 0);
      path.lineTo(1, 8);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = mine ? LegacyStyle.accent : Colors.white,
    );
  }

  @override
  bool shouldRepaint(LegacyBubbleTail oldDelegate) =>
      oldDelegate.mine != mine || oldDelegate.first != first;
}

class LegacySelectionMarker extends CustomPainter {
  const LegacySelectionMarker();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(16, 1.5)
      ..quadraticBezierTo(1.5, 1.5, 1.5, 16)
      ..lineTo(1.5, size.height - 16)
      ..quadraticBezierTo(1.5, size.height - 1.5, 16, size.height - 1.5);
    canvas.drawPath(
      path,
      Paint()
        ..color = LegacyStyle.accent
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(LegacySelectionMarker oldDelegate) => false;
}

/// Legacy's white search/composer fields, including their CSS focus halo.
class LegacyFieldSurface extends StatefulWidget {
  final Widget child;
  final double radius;
  final bool enabled;
  const LegacyFieldSurface({
    super.key,
    required this.child,
    this.radius = 14,
    this.enabled = true,
  });
  @override
  State<LegacyFieldSurface> createState() => _LegacyFieldSurfaceState();
}

class _LegacyFieldSurfaceState extends State<LegacyFieldSurface> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (value) => setState(() => focused = value),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        boxShadow: !widget.enabled
            ? null
            : [
                if (focused)
                  const BoxShadow(color: Color(0xffdbeafe), spreadRadius: 3),
                ...LegacyStyle.shadow,
              ],
      ),
      child: widget.child,
    ),
  );
}
