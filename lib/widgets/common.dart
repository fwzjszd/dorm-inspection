// 通用 UI 组件：页面内容的透明 Material 层、分组卡片、分区小标题

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// MiuixScaffold 的 MiuixSurface 不提供 Material 祖先，而 Material 的
/// TextField（MiuixTextField 内部使用）、ListTile、InkWell 都需要它；
/// 同时 Material 会注入正常的 DefaultTextStyle，避免文字出现黄色双下划线。
/// 透明材质不影响 miuix 的背景与视觉，仅补祖先能力。
class MiuixPageContent extends StatelessWidget {
  const MiuixPageContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(type: MaterialType.transparency, child: child);
  }
}

/// miuix 设置页风格的分组卡片容器
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: MiuixHorizontalDivider(),
          ),
        );
      }
    }
    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: 12),
      child: MiuixCard(
        cornerRadius: 18,
        child: Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}

/// 分区标题
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 8),
      child: MiuixText(
        text,
        style: MiuixTheme.of(context).textStyles.subtitle,
        color: MiuixTheme.of(context).colors.onBackgroundVariant,
      ),
    );
  }
}

/// 导出方式弹窗中的一个可选项
class ExportOption {
  const ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

/// 导出方式选择弹窗：选项由调用方按需组合传入
Future<void> showExportOptionsSheet(
  BuildContext context, {
  required List<ExportOption> options,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final ExportOption o in options)
              ListTile(
                leading: Icon(o.icon),
                title: Text(o.title),
                subtitle: Text(o.subtitle),
                onTap: () {
                  Navigator.pop(ctx);
                  o.onTap();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 滑动项右侧露出的圆形动作按钮数据
class SlideTileAction {
  const SlideTileAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

/// 左滑露出右侧圆形操作按钮的列表项容器（MIUI 标准方向）。
/// 同一组列表传入同一个 [activeNotifier] 可保证同时只有一项展开。
class SlideActionTile extends StatefulWidget {
  const SlideActionTile({
    super.key,
    required this.tag,
    required this.child,
    required this.actions,
    this.activeNotifier,
    this.onTap,
    this.actionExtent = 132,
  });

  final String tag;
  final Widget child;
  final List<SlideTileAction> actions;
  final ValueNotifier<String?>? activeNotifier;
  final VoidCallback? onTap;

  /// 全部操作按钮占用的总宽度
  final double actionExtent;

  @override
  State<SlideActionTile> createState() => _SlideActionTileState();
}

class _SlideActionTileState extends State<SlideActionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  // 手势方向锁：在 ListView 中，GestureDetector 的水平拖动会与列表的
  // 垂直滚动竞争并经常判负，导致右滑无反应。改用 Listener 直接处理指针，
  // 一旦确认是水平拖动就自行消费事件，不再走手势竞技场。
  bool _pointerDown = false;
  bool _horizontal = false;
  Offset _lastPos = Offset.zero;
  Duration _lastTime = Duration.zero;
  double _lastDx = 0;

  @override
  void initState() {
    super.initState();
    widget.activeNotifier?.addListener(_onActiveChanged);
  }

  @override
  void didUpdateWidget(covariant SlideActionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeNotifier != widget.activeNotifier) {
      oldWidget.activeNotifier?.removeListener(_onActiveChanged);
      widget.activeNotifier?.addListener(_onActiveChanged);
    }
  }

  void _onActiveChanged() {
    final String? active = widget.activeNotifier?.value;
    if (active != widget.tag && _ctrl.value > 0) {
      _ctrl.reverse();
    }
  }

  void _open() {
    _ctrl.forward();
    if (widget.activeNotifier != null) {
      widget.activeNotifier!.value = widget.tag;
    }
  }

  void _settle(double velocity) {
    if (velocity < -300 || (velocity <= 300 && _ctrl.value > 0.45)) {
      _open();
    } else {
      _ctrl.reverse();
    }
  }

  void _handleTap() {
    if (_ctrl.value > 0) {
      _ctrl.reverse();
      return;
    }
    widget.onTap?.call();
  }

  @override
  void dispose() {
    widget.activeNotifier?.removeListener(_onActiveChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // 底层：右侧圆形操作按钮
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                for (final SlideTileAction a in widget.actions)
                  Padding(
                    padding: EdgeInsets.only(
                      left: 6,
                      right: identical(a, widget.actions.last) ? 0 : 6,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          _ctrl.reverse();
                          a.onTap();
                        },
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: a.color,
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: a.color.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(a.icon, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 前景：可左滑的内容（左移露出右侧操作按钮）
        AnimatedBuilder(
          animation: _ctrl,
          builder: (BuildContext context, _) {
            final double dx = _ctrl.value * widget.actionExtent;
            return Transform.translate(
              offset: Offset(-dx, 0),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (PointerDownEvent e) {
                  _pointerDown = true;
                  _horizontal = false;
                  _lastPos = e.position;
                  _lastTime = e.timeStamp;
                },
                onPointerMove: (PointerMoveEvent e) {
                  if (!_pointerDown) return;
                  final double ddx = e.position.dx - _lastPos.dx;
                  final double ddy = e.position.dy - _lastPos.dy;
                  final Duration dtDur = e.timeStamp - _lastTime;
                  _lastPos = e.position;
                  _lastTime = e.timeStamp;
                  // 尚未决定方向时，先按位移主导方向锁定
                  if (!_horizontal) {
                    if (ddx.abs() < 4 && ddy.abs() < 4) return;
                    if (ddx.abs() < ddy.abs()) {
                      // 垂直拖动：交给 ListView 处理滚动
                      _pointerDown = false;
                      return;
                    }
                    _horizontal = true;
                  }
                  final double dt = dtDur.inMicroseconds / 1e6;
                  _lastDx = dt > 0 ? ddx / dt : 0;
                  // 左滑 ddx<0 → value 增大 → 内容左移展开按钮
                  final double next = (_ctrl.value - ddx / widget.actionExtent)
                      .clamp(0.0, 1.0);
                  _ctrl.value = next;
                },
                onPointerUp: (PointerUpEvent e) {
                  if (!_pointerDown) return;
                  final bool wasHorizontal = _horizontal;
                  final double vx = wasHorizontal ? _lastDx : 0.0;
                  _pointerDown = false;
                  _horizontal = false;
                  if (wasHorizontal) {
                    _settle(vx);
                  } else {
                    _handleTap();
                  }
                },
                onPointerCancel: (PointerCancelEvent e) {
                  _pointerDown = false;
                  _horizontal = false;
                },
                child: widget.child,
              ),
            );
          },
        ),
      ],
    );
  }
}
