// 主框架：液态玻璃胶囊底栏（首页 / 设置）
//
// 视觉与交互移植自 BiliMax-APK（moe.mcns.BiliMax）MainActivity.kt 中的
// CapsuleBottomBar / CapsuleTabItem，并直接复用 flutter_miuix 内置的
// OS4 液态玻璃 shader 栈（源自 compose-miuix-ui/miuix，Apache-2.0）：
//   外边距 20、底部 8、外高 68、导轨 64、滑块高 56、inset 4；
//   ① 底部轨道：MiuixGlassPanel(shading:false) 磨砂模糊玻璃
//      （puredThinGlass 材质 + 真高斯模糊 + 棱边 stroke），按压整体缩放 1.08；
//   ② 滑动按钮：MiuixGlass(shading:true) 透明折射玻璃
//      （lens 透镜折射 + 镜面棱边高光 + 边缘色散），按压缩放 1.28；
//   背景采样：MiuixLayerBackdropCapture 捕获页面层（Pager 兄弟层），
//      悬浮玻璃栏作为 capture 之外的兄弟节点按全局偏移取样；
//   反向滑动：页面向左滑（切换到右页）时滑块向右移动，与页面内容运动方向相反，
//      pillLeft = 4 + position * tabWidth，松手由 PageScrollPhysics 自动吸附；
//   jelly 物理：横拖速度驱动滑块挤压拉伸（scaleX/scaleY 体积近似守恒）+
//      水平方向剪切形变，松手以带轻微超调的弹簧回位；
//   触摸径向高光：圆心跟随触点，半径 min(w,h)*1.5，
//      neutral @ (0.15·reveal) → 透明，叠加在折射玻璃之上；
//   reveal（spring stiffness 1000 / damping 1）在按压或分页未对齐时到 1；
//   Tab：图标 22 + 间距 6 + 文字 14/Medium；
//   深色选中色 0xFF7FCFFF，未选中 onSurface @ 0.60，颜色随分页进度 lerp；
//   整栏横拖：delta * 1.6 * pageWidth / barWidth 反向投给 Pager。

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_miuix/miuix.dart';

import '../widgets/layer_backdrop_capture.dart';
import 'home_page.dart';
import 'settings_page.dart';

const double _kBarHeight = 68;
const double _kRailHeight = 64;
const double _kPillHeight = 56;
const double _kPillPad = 4;
const double _kSideMargin = 20;
const double _kBottomGap = 8;
const double _kDragSensitivity = 1.6;
const Color _kSelectedColor = Color(0xFF7FCFFF);

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final PageController _pager = PageController();
  // 页面层背景快照：供悬浮玻璃栏取 Pager 兄弟层像素做模糊/折射
  final MiuixLayerBackdrop _barBackdrop = MiuixLayerBackdrop();
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
    _barBackdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final MediaQueryData mq = MediaQuery.of(context);
    // 内容底部留白：外高 68 + 安全区 + 底部间隙
    final double navReserve =
        _kBarHeight +
        (mq.padding.bottom != 0 ? mq.padding.bottom : 12) +
        _kBottomGap;

    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: colors.surface,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              // 捕获页面内容层：玻璃节点必须在 capture 之外（防反馈采样）
              // pixelRatio 固定 1.0：玻璃消费端采样比上限即 1（每逻辑像素 1 纹素），
              // 默认按设备 DPR(~3) 会让每帧全屏快照填充率暴涨约 9 倍，造成滑动时
              // 底栏后方内容掉帧鬼畜；降到 1.0 观感无损而 GPU 开销大幅下降。
              // 使用按需捕获版本：miuix 自带捕获每帧无条件出图，与玻璃重绘构成
              // 永不停止的快照→重绘循环（静止也 60fps 全屏截图），是进入应用即
              // 严重卡顿的主因；本版本仅在内容/图层签名变化时更新快照。
              child: LayerBackdropCapture(
                backdrop: _barBackdrop,
                pixelRatio: 1.0,
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
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _CapsuleBar(
                pager: _pager,
                backdrop: _barBackdrop,
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

/// 胶囊底栏（规格见文件头说明）
class _CapsuleBar extends StatefulWidget {
  const _CapsuleBar({
    required this.pager,
    required this.backdrop,
    required this.selected,
    required this.onSelect,
  });

  final PageController pager;
  final MiuixBackdrop backdrop;
  final int selected;
  final ValueChanged<int> onSelect;

  static const int tabsCount = 2;

  @override
  State<_CapsuleBar> createState() => _CapsuleBarState();
}

class _CapsuleBarState extends State<_CapsuleBar>
    with TickerProviderStateMixin {
  // 导轨按压缩放（目标 1.08，spring damping 1 / stiffness 1000）
  late final AnimationController _railScale = AnimationController(
    vsync: this,
    value: 1,
    lowerBound: 0.5,
    upperBound: 2,
  );
  // 药丸按压缩放（目标 1.28，同参数弹簧）
  late final AnimationController _knobScale = AnimationController(
    vsync: this,
    value: 1,
    lowerBound: 0.5,
    upperBound: 2,
  );
  // 玻璃附加层（触摸高光）显隐：按压或拖动分页时到 1
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    value: 0,
  );
  // jelly 形变：>0 向右拉伸，<0 向左拉伸；0 为静止胶囊
  late final AnimationController _jelly = AnimationController(
    vsync: this,
    value: 0,
    lowerBound: -1,
    upperBound: 1,
  );

  double _barWidth = 0;
  bool _pressed = false;
  bool _revealOn = false;
  // 触摸点（相对 68 高外层容器的局部坐标）
  Offset? _touchLocal;
  // 横拖时持有的 Pager 拖拽会话（DragScrollActivity，自带边界夹取与松手吸附）
  Drag? _pagerDrag;
  // jelly 速度采样
  Duration? _lastDragTime;
  double _dragVelocity = 0; // 手指横向速度 px/s（右为正）

  Future<void> _springTo(AnimationController c, double target) {
    return c.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 1000, ratio: 1),
        c.value,
        target,
        0,
      ),
    );
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    _pressed = pressed;
    _springTo(_railScale, pressed ? 1.08 : 1);
    _springTo(_knobScale, pressed ? 1.28 : 1);
    if (!pressed) _settleJelly();
  }

  // 横拖直接驱动 Pager（灵敏度 1.6，按 bar 宽度折算到整页宽度）
  void _onDragStart(DragStartDetails d) {
    if (!widget.pager.hasClients) return;
    _lastDragTime = d.sourceTimeStamp;
    _dragVelocity = 0;
    _pagerDrag = widget.pager.position.drag(d, () {
      _pagerDrag = null;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.pager.hasClients || _barWidth <= 0) return;
    final double pageWidth = widget.pager.position.viewportDimension;
    if (pageWidth <= 0) return;

    // 速度采样（手指坐标系：右滑为正）
    final Duration? t = d.sourceTimeStamp;
    if (_lastDragTime != null && t != null) {
      final double dt =
          (t - _lastDragTime!).inMicroseconds / Duration.microsecondsPerSecond;
      if (dt >= 0.001) {
        final double v = d.delta.dx / dt;
        // 低通滤波，避免单帧抖动
        _dragVelocity = _dragVelocity == 0 ? v : _dragVelocity * 0.5 + v * 0.5;
        // 滑块与手指反向运动：右滑时滑块向左拉伸
        _driveJelly(-_dragVelocity);
      }
    }
    _lastDragTime = t;

    // 横向上滚动量与手指 dx 同方向，但 Pager 正向偏移对应手指向左，故取反
    _pagerDrag?.update(
      DragUpdateDetails(
        sourceTimeStamp: d.sourceTimeStamp,
        delta: Offset(
          -d.delta.dx * _kDragSensitivity * pageWidth / _barWidth,
          0,
        ),
        primaryDelta: -d.delta.dx * _kDragSensitivity * pageWidth / _barWidth,
        globalPosition: d.globalPosition,
      ),
    );
  }

  // 拖动中：按速度即时给形变量（夹到 ±0.18）
  void _driveJelly(double knobVelocity) {
    const double referenceVelocity = 2200; // px/s 对应满形变
    final double target = (knobVelocity / referenceVelocity)
        .clamp(-0.18, 0.18)
        .toDouble();
    _jelly.value = _jelly.value * 0.55 + target * 0.45;
  }

  // 松手：带轻微超调的弹簧回 0（ratio < 1 产生 wobble）
  void _settleJelly() {
    _dragVelocity = 0;
    _jelly.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: 380,
          ratio: 0.62,
        ),
        _jelly.value,
        0,
        0,
      ),
    );
  }

  void _onDragEnd() {
    final Drag? drag = _pagerDrag;
    // 先断开引用，避免后续回调重入
    _pagerDrag = null;
    _setPressed(false);
    try {
      // 必须提供非空 primaryVelocity：零速度松手，由 PageScrollPhysics
      // 弹道吸附到最近页。传 null 在 release 下会在框架内抛异常，
      // 导致 goBallistic 不执行（不吸附）且后续复位被打断（jelly 卡滞）。
      drag?.end(DragEndDetails(primaryVelocity: 0.0));
    } finally {
      // 无论如何保证按压态与形变弹簧复位
      _settleJelly();
    }
  }

  void _onDragCancel() {
    final Drag? drag = _pagerDrag;
    _pagerDrag = null;
    _setPressed(false);
    try {
      // cancel 内部即 goBallistic(0.0)，同样会吸附最近页
      drag?.cancel();
    } finally {
      _settleJelly();
    }
  }

  @override
  void dispose() {
    _railScale.dispose();
    _knobScale.dispose();
    _reveal.dispose();
    _jelly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool isDark = colors.background.computeLuminance() < 0.5;
    final Color neutral = isDark ? Colors.white : Colors.black;
    final Color unselectedColor = colors.onSurface.withValues(alpha: 0.60);
    final Color glassFill = neutral.withValues(alpha: 0.03);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kSideMargin,
          0,
          _kSideMargin,
          _kBottomGap,
        ),
        child: SizedBox(
          height: _kBarHeight,
          width: double.infinity,
          child: Listener(
            onPointerDown: (PointerDownEvent e) {
              _touchLocal = e.localPosition;
              _setPressed(true);
            },
            onPointerMove: (PointerMoveEvent e) {
              _touchLocal = e.localPosition;
            },
            onPointerUp: (_) => _setPressed(false),
            onPointerCancel: (_) => _setPressed(false),
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable?>[
                widget.pager,
                _railScale,
                _knobScale,
                _reveal,
                _jelly,
              ]),
              builder: (BuildContext context, _) {
                final double position =
                    (widget.pager.hasClients
                            ? widget.pager.page ?? widget.selected.toDouble()
                            : widget.selected.toDouble())
                        .clamp(0.0, (_CapsuleBar.tabsCount - 1).toDouble());

                // reveal：按压中，或分页未对齐（|偏移小数| > 0.01）
                final bool revealOn =
                    _pressed || (position - position.round()).abs() > 0.01;
                if (revealOn != _revealOn) {
                  _revealOn = revealOn;
                  _springTo(_reveal, revealOn ? 1 : 0);
                }

                return LayoutBuilder(
                  builder: (BuildContext ctx, BoxConstraints c) {
                    final double w = c.maxWidth;
                    _barWidth = w;
                    final double tabWidth =
                        (w - _kPillPad * 2) / _CapsuleBar.tabsCount;
                    // 各 Tab 选中进度：首页 1-pos，设置 pos
                    final double homeAmount = (1 - position).clamp(0.0, 1.0);
                    final double settingsAmount = position.clamp(0.0, 1.0);
                    // 页面向左滑（pos 增大）时滑块右移，与页面内容运动方向相反
                    final double pillLeft = _kPillPad + position * tabWidth;
                    final double pillTop = (_kBarHeight - _kPillHeight) / 2;
                    // jelly 形变：体积近似守恒的 squash-stretch + 水平剪切
                    final double d = _jelly.value;
                    final double sx = 1 + d.abs();
                    final double sy = 1 - d.abs() * 0.6;
                    final double shear = -d * 0.22;

                    return Stack(
                      children: <Widget>[
                        // ① 导轨：高 64，磨砂模糊玻璃胶囊（仅模糊混色 + 棱边）
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_kBarHeight - _kRailHeight) / 2,
                          height: _kRailHeight,
                          child: Transform.scale(
                            scale: _railScale.value,
                            child: IgnorePointer(
                              child: MiuixGlassPanel(
                                backdrop: widget.backdrop,
                                material: MiuixGlassMaterials.puredThinGlass(
                                  isDark,
                                ),
                                shape: const MiuixGlassShape(
                                  cornerRadius: 999,
                                  smoothing: 1,
                                ),
                                fill: colors.surface.withValues(alpha: 0.04),
                                shading: false,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                        // ② 选中药丸：高 56、宽 (W-8)/N
                        //    透明折射玻璃（lens + 棱边镜面高光 + 色散），
                        //    叠加 jelly 速度形变、按压缩放与触摸径向高光
                        Positioned(
                          left: pillLeft,
                          top: pillTop,
                          height: _kPillHeight,
                          width: tabWidth,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..scaleByDouble(sx, sy, 1, 1)
                              ..setEntry(0, 1, shear),
                            child: Transform.scale(
                              scale: _knobScale.value,
                              child: Stack(
                                fit: StackFit.passthrough,
                                children: <Widget>[
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: MiuixGlass(
                                        backdrop: widget.backdrop,
                                        material:
                                            MiuixGlassMaterials.puredThinGlass(
                                              isDark,
                                            ),
                                        shape: const MiuixGlassShape(
                                          cornerRadius: 999,
                                          smoothing: 1,
                                        ),
                                        fill: glassFill,
                                        // 透明透镜：折射 + 棱边 + 色散
                                        shading: true,
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  ),
                                  // 触摸径向高光（与现有一致，叠加在玻璃之上）
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: CustomPaint(
                                        painter: _TouchGlowPainter(
                                          reveal: _reveal.value,
                                          neutral: neutral,
                                          touchPoint: _touchLocal == null
                                              ? null
                                              : _touchLocal! -
                                                    Offset(pillLeft, pillTop),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // ③ Tab 行：高 64，水平 padding 4
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_kBarHeight - _kRailHeight) / 2,
                          height: _kRailHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _kPillPad,
                            ),
                            child: Row(
                              children: <Widget>[
                                _CapsuleTabItem(
                                  icon: Icons.home_rounded,
                                  label: '首页',
                                  color: Color.lerp(
                                    unselectedColor,
                                    _kSelectedColor,
                                    homeAmount,
                                  )!,
                                  onTap: () => widget.onSelect(0),
                                ),
                                _CapsuleTabItem(
                                  icon: Icons.settings_rounded,
                                  label: '设置',
                                  color: Color.lerp(
                                    unselectedColor,
                                    _kSelectedColor,
                                    settingsAmount,
                                  )!,
                                  onTap: () => widget.onSelect(1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ④ 整栏横拖手势（translucent：点击仍由 Tab 接管）
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragStart: _onDragStart,
                            onHorizontalDragUpdate: _onDragUpdate,
                            onHorizontalDragEnd: (_) => _onDragEnd(),
                            onHorizontalDragCancel: _onDragCancel,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 触摸径向高光：reveal 控制透明度，半径 min(w,h)*1.5，
/// neutral@(0.15·reveal) → 透明，圆心跟随触点（夹到药丸内）。
class _TouchGlowPainter extends CustomPainter {
  _TouchGlowPainter({
    required this.reveal,
    required this.neutral,
    required this.touchPoint,
  });

  final double reveal;
  final Color neutral;
  // 触摸点在药丸坐标系内的位置（未夹取，paint 内夹到药丸内）；null 时取中心
  final Offset? touchPoint;

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal <= 0) return;
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final Offset center = touchPoint == null
        ? size.center(Offset.zero)
        : Offset(
            touchPoint!.dx.clamp(0.0, size.width),
            touchPoint!.dy.clamp(0.0, size.height),
          );
    final double radius = math.min(size.width, size.height) * 1.5;
    final Paint highlight = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          neutral.withValues(alpha: 0.15 * reveal),
          neutral.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawCircle(center, radius, highlight);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TouchGlowPainter old) {
    return old.reveal != reveal ||
        old.neutral != neutral ||
        old.touchPoint != touchPoint;
  }
}

/// 胶囊 Tab：图标 22 + 间距 6 + 文字 14/Medium，内容色随选中进度 lerp
class _CapsuleTabItem extends StatelessWidget {
  const _CapsuleTabItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 6),
            MiuixText(
              label,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
