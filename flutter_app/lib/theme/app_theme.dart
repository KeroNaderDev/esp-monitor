import 'package:flutter/material.dart';

/// Shared design tokens for the whole app.
class AppColors {
  static const bg = Color(0xFF0F0F1A);
  static const card = Color(0xFF1A1A2E);
  static const indigo = Color(0xFFA5B4FC);
  static const cyan = Color(0xFF7DD3FC);
  static const orange = Color(0xFFFF9E3D);
  static const orangeDeep = Color(0xFFFF6A2E);
  static const green = Color(0xFF4ADE80);
  static const red = Color(0xFFF87171);
  static const muted = Color(0xFF94A3B8);
  static const faint = Color(0xFF64748B);
  static const white = Colors.white;
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.indigo,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}

/// Soft ambient background: two blurred-tint circles over the base color.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -130,
          right: -130,
          child: _glow(300, AppColors.indigo.withValues(alpha: 0.15)),
        ),
        Positioned(
          bottom: -150,
          left: -150,
          child: _glow(340, AppColors.cyan.withValues(alpha: 0.09)),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Card with a thin gradient border (online = green/cyan, offline = red).
class GradientCard extends StatelessWidget {
  final bool online;
  final Widget child;
  final EdgeInsets padding;

  const GradientCard({
    super.key,
    required this.online,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final edge = online ? AppColors.green : AppColors.red;
    return Container(
      padding: const EdgeInsets.all(1.3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            edge.withValues(alpha: 0.55),
            edge.withValues(alpha: 0.08),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(21),
        ),
        child: child,
      ),
    );
  }
}

/// Small gradient logo tile used in headers.
class LogoTile extends StatelessWidget {
  final double size;
  const LogoTile({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF22D3EE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.thermostat,
        color: Colors.white,
        size: size * 0.58,
      ),
    );
  }
}

/// Status pill: green "Live" or red "Offline".
class StatusPill extends StatelessWidget {
  final bool online;
  const StatusPill({super.key, required this.online});

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.green : AppColors.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: color, animate: online, size: 8),
          const SizedBox(width: 7),
          Text(
            online ? 'Live' : 'Offline',
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsing status dot (static when offline).
class PulseDot extends StatefulWidget {
  final Color color;
  final bool animate;
  final double size;
  const PulseDot({
    super.key,
    required this.color,
    required this.animate,
    this.size = 12,
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_ctrl),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.7),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

/// Plays a fade+slide entrance once (keyed by device, survives rebuilds).
class Entrance extends StatefulWidget {
  final int index;
  final Widget child;
  const Entrance({super.key, required this.index, required this.child});

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void initState() {
    super.initState();
    final delay = (widget.index * 70).clamp(0, 420);
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.13), end: Offset.zero)
            .animate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic)),
        child: widget.child,
      ),
    );
  }
}
