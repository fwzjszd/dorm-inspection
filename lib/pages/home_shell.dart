// 主框架：液态玻璃底栏（首页 / 设置）
//
// 三层结构与参数移植自开源项目 Kyant0/AndroidLiquidGlass（Apache-2.0）
// catalog 示例 LiquidBottomTabs.kt：
//   ① 导轨：高 64，全胶囊，内边距 4；blur(8dp) + vibrancy + lens，
//      深色表面 0xFF121212 @ 0.4
//   ② 图标捕获层：AGSL 专用，Flutter 无等价物，省略（选中色直接 tint 内容）
//   ③ 选中药丸：高 56、宽 (W-8)/N，清晰无模糊；白@0.1 表面，
//      高光白0.5 / 外阴影黑0.1(半径24) / 内阴影黑0.15(半径8) 随按压进度，
//      按压缩放 78/56，弹簧 stiffness 1000 / damping 1
// 注：lens 折射依赖 AGSL RuntimeShader、vibrancy 是作用于 backdrop 的
// 饱和度 1.5 色彩矩阵，Flutter 均无跨平台等价 API，按既定方案以
// 「清晰药丸 + 边缘高光 + 内/外阴影」近似，绝不使用 wearos工具箱自研代码。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_miuix/miuix.dart';

import 'home_page.dart';
import 'settings_page.dart';

// 开源示例深色规格（LiquidBottomTabs.kt）
const Color _kAccent = Color(0xFF0091FF);
const Color _kContainer = Color(0x66121212); // 0xFF121212 @ alpha 0.4
const double _kBarHeight = 64;
const double _kPillHeight = 56;
const double _kPadding = 4;
const double _kBlurSigma = 8; // blur(8dp)

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _pager = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pager.addListener(_onPager);
  }

  void _onPager() {
    final int next = (_pager.page ?? 0).round();
    if (next != _index) setState(() => _index = next);
  }

  Future<void> _select(int i) async {
    await _pager.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pager.removeListener(_onPager);
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MediaQueryData mq = MediaQuery.of(context);
    // 内容底部留白：导轨 64 + 安全区 + 呼吸间隙
    final double navReserve =
        _kBarHeight + (mq.padding.bottom != 0 ? mq.padding.bottom : 12) + 10;

    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: colors.surface,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: MediaQuery(
                data: mq.copyWith(
                  padding: mq.padding.copyWith(bottom: navReserve),
                ),
                child: PageView(
                  controller: _pager,
                  children: const <Widget>[HomePage(), SettingsPage()],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _LiquidGlassBar(
                pager: _pager,
                selected: _index,
                onSelect: _select,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 液态玻璃底栏（三层结构见文件头说明）
class _LiquidGlassBar extends StatefulWidget {
  const _LiquidGlassBar({
    required this.pager,
    required this.selected,
    required this.onSelect,
  });

  final PageController pager;
  final int selected;
  final ValueChanged<int> onSelect;

  static const int tabsCount = 2;

  @override
  State<_LiquidGlassBar> createState() => _LiquidGlassBarState();
}

class _LiquidGlassBarState extends State<_LiquidGlassBar>
    with TickerProviderStateMixin {
  // 药丸位置（单位：tab 索引浮点，0..tabsCount-1）
  late final AnimationController _pos = AnimationController(
    vsync: this,
    value: widget.selected.toDouble(),
  );
  // 按压进度 0..1（spring damping 1 / stiffness 1000）
  late final AnimationController _press = AnimationController(
    vsync: this,
    value: 0,
  );
  // 药丸缩放（目标 78/56，spring damping 0.6 / stiffness 250）
  late final AnimationController _pillScale = AnimationController(
    vsync: this,
    value: 1,
    lowerBound: 0.5,
    upperBound: 2,
  );
  // 拖拽时整栏反向回弹位移（px，spring damping 1 / stiffness 300）
  late final AnimationController _panel = AnimationController(
    vsync: this,
    value: 0,
  );

  bool _dragging = false;
  double _dragAccum = 0;
  Offset _pressPoint = Offset.zero;
  bool _hasPressPoint = false;

  late final Listenable _repaint = Listenable.merge(<Listenable>[
    _pos,
    _press,
    _pillScale,
    _panel,
  ]);

  @override
  void initState() {
    super.initState();
    widget.pager.addListener(_syncFromPager);
  }

  @override
  void didUpdateWidget(covariant _LiquidGlassBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pager != widget.pager) {
      oldWidget.pager.removeListener(_syncFromPager);
      widget.pager.addListener(_syncFromPager);
    }
  }

  // 内容页滑动时药丸跟随手指（仅在非药丸拖拽时）
  void _syncFromPager() {
    if (_dragging || !widget.pager.hasClients) return;
    _pos.value = widget.pager.page ?? widget.selected.toDouble();
  }

  Future<void> _springTo(
    AnimationController c,
    double target, {
    required double stiffness,
    required double ratio,
  }) {
    return c.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness,
          ratio: ratio,
        ),
        c.value,
        target,
        0,
      ),
    );
  }

  // EaseOut.transform，与开源 panelOffset 曲线一致
  double _easeOut(double x) => 1 - math.pow(1 - x, 3).toDouble();

  void _onDragStart(DragStartDetails d) {
    setState(() {
      _dragging = true;
      _hasPressPoint = true;
      _pressPoint = d.localPosition;
    });
    _springTo(_press, 1, stiffness: 1000, ratio: 1);
    _springTo(_pillScale, 78 / _kPillHeight, stiffness: 250, ratio: 0.6);
  }

  void _onDragUpdate(DragUpdateDetails d, double tabWidth, double barWidth) {
    final double next = (_pos.value + d.delta.dx / tabWidth).clamp(
      0.0,
      (_LiquidGlassBar.tabsCount - 1).toDouble(),
    );
    _pos.value = next;
    _dragAccum += d.delta.dx;
    final double frac = (_dragAccum / barWidth).clamp(-1.0, 1.0);
    _panel.value = _kPadding * frac.sign * _easeOut(frac.abs());
    setState(() => _pressPoint = d.localPosition);
  }

  void _onDragEnd() {
    final int target = _pos.value.round().clamp(
      0,
      _LiquidGlassBar.tabsCount - 1,
    );
    _dragging = false;
    _dragAccum = 0;
    _springTo(_pos, target.toDouble(), stiffness: 1000, ratio: 1);
    _springTo(_panel, 0, stiffness: 300, ratio: 1);
    _springTo(_press, 0, stiffness: 1000, ratio: 1);
    _springTo(_pillScale, 1, stiffness: 250, ratio: 0.6);
    widget.onSelect(target);
  }

  @override
  void dispose() {
    widget.pager.removeListener(_syncFromPager);
    _pos.dispose();
    _press.dispose();
    _pillScale.dispose();
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color unselectedFg = Colors.white.withValues(alpha: 0.6);

    return SafeArea(
      top: false,
      child: Padding(
        // 开源 demo BottomTabsContent：horizontal = 36dp
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 10),
        child: AnimatedBuilder(
          animation: _repaint,
          builder: (BuildContext context, _) {
            final double p = _press.value;
            // 导轨按压整体放大：lerp(1, 1 + 16/barWidth, pressProgress)
            return LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints c) {
                final double w = c.maxWidth;
                final double railScale = 1 + 16 / w * p;
                final double tabWidth =
                    (w - _kPadding * 2) / _LiquidGlassBar.tabsCount;

                final Widget bar = SizedBox(
                  height: _kBarHeight,
                  width: w,
                  child: Stack(
                    children: <Widget>[
                      // ① 导轨：模糊胶囊（blur 8 + 容器色），vibrancy/lens 无 Flutter 等价物
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        height: _kBarHeight,
                        child: Transform.scale(
                          scale: railScale,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              _kBarHeight / 2,
                            ),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: _kBlurSigma,
                                sigmaY: _kBlurSigma,
                                tileMode: TileMode.clamp,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _kContainer,
                                  borderRadius: BorderRadius.circular(
                                    _kBarHeight / 2,
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ③ 选中药丸：清晰、无模糊，位置 = pos * tabWidth
                      Positioned(
                        left: _kPadding + _pos.value * tabWidth,
                        top: _kPadding,
                        height: _kPillHeight,
                        width: tabWidth,
                        child: Transform.scale(
                          scale: _pillScale.value,
                          child: _Pill(
                            press: p,
                            pressPoint: _hasPressPoint ? _pressPoint : null,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      // 内容行（高 64，水平 padding 4；图标 28 + 文字 12）
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _kPadding,
                          ),
                          child: Row(
                            children: <Widget>[
                              _TabItem(
                                icon: Icons.home_rounded,
                                label: '首页',
                                selected: widget.selected == 0,
                                unselectedColor: unselectedFg,
                                iconScale: 1 + 0.2 * p,
                                onTap: () => widget.onSelect(0),
                              ),
                              _TabItem(
                                icon: Icons.settings,
                                label: '设置',
                                selected: widget.selected == 1,
                                unselectedColor: unselectedFg,
                                iconScale: 1 + 0.2 * p,
                                onTap: () => widget.onSelect(1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 药丸拖拽手势层（只接管水平拖拽，点击穿透给 Tab）
                      Positioned(
                        left: _kPadding + _pos.value * tabWidth,
                        top: _kPadding,
                        height: _kPillHeight,
                        width: tabWidth,
                        child: GestureDetector(
                          // translucent：水平拖拽由药丸接管，普通点击穿透给 Tab
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: (DragStartDetails d) =>
                              _onDragStart(d),
                          onHorizontalDragUpdate: (DragUpdateDetails d) =>
                              _onDragUpdate(d, tabWidth, w),
                          onHorizontalDragEnd: (_) => _onDragEnd(),
                          onHorizontalDragCancel: _onDragEnd,
                        ),
                      ),
                    ],
                  ),
                );

                return Transform.translate(
                  offset: Offset(_panel.value, 0),
                  child: bar,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// 选中药丸表面：白@0.1（随按压淡出）+ 黑@0.03*press；
/// 高光 / 外阴影 / 内阴影均随按压进度出现（开源 onDrawSurface + Highlight/Shadow）
class _Pill extends StatelessWidget {
  const _Pill({
    required this.press,
    required this.pressPoint,
    required this.child,
  });

  final double press;
  final Offset? pressPoint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(_kPillHeight / 2);
    final Color surface = Color.lerp(
      Colors.white.withValues(alpha: 0.10),
      Colors.black.withValues(alpha: 0.03),
      press,
    )!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Shadow：黑 0.1，半径 24，y 偏移 4（alpha = press）
        boxShadow: press > 0
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10 * press),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: radius,
            // Highlight.Default：白 0.5 / Plus / 45°，alpha = press；
            // 平时保留 0.12 细边保证药丸轮廓可读
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12 + 0.38 * press),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 按压处径向高光（InteractiveHighlight 的 shader 近似）
              if (press > 0 && pressPoint != null)
                CustomPaint(
                  painter: _PressHighlightPainter(
                    point: pressPoint!,
                    flatAlpha: 0.08 * press,
                    radialAlpha: 0.15 * press,
                  ),
                )
              else if (press > 0)
                ColoredBox(color: Colors.white.withValues(alpha: 0.08 * press)),
              // InnerShadow：黑 0.15、半径 8*press、向下
              if (press > 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.15 * press),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, 8 / _kPillHeight],
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 按压径向高光：底层平涂白 0.08 + 触点周围白 0.15（Plus 混合的近似）
class _PressHighlightPainter extends CustomPainter {
  _PressHighlightPainter({
    required this.point,
    required this.flatAlpha,
    required this.radialAlpha,
  });

  final Offset point;
  final double flatAlpha;
  final double radialAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: flatAlpha),
    );
    final double r = size.shortestSide * 1.5;
    final Offset center = Offset(
      point.dx.clamp(0, size.width),
      point.dy.clamp(0, size.height),
    );
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.white.withValues(alpha: radialAlpha),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const <double>[0, 0.5],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _PressHighlightPainter old) =>
      old.point != point ||
      old.flatAlpha != flatAlpha ||
      old.radialAlpha != radialAlpha;
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.unselectedColor,
    required this.iconScale,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color unselectedColor;
  final double iconScale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? _kAccent : unselectedColor;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Transform.scale(
              scale: selected ? iconScale : 1,
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 2),
            MiuixText(
              label,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
