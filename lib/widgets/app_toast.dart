// 全局悬浮提示：logo + 提示文字 + 圆角悬浮窗（替代 miuix Snackbar）
// 用法与原来一致：AppScope.of(context).snackbar.showSnackbar('提示内容')

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

/// 提示状态载体，挂在 AppScope 上全局共享
class AppToastState extends ChangeNotifier {
  String _message = '';
  int _seq = 0;

  String get message => _message;

  /// 每次调用自增，用于区分内容相同的两条连续提示
  int get seq => _seq;

  /// 兼容原 MiuixSnackbarHostState.showSnackbar 调用方式
  void showSnackbar(String message) {
    _message = message;
    _seq++;
    notifyListeners();
  }
}

/// 悬浮提示宿主：置于 MaterialApp.builder 的 Stack 顶层
class AppToastHost extends StatefulWidget {
  const AppToastHost({super.key, required this.state});

  final AppToastState state;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _timer;
  int _shownSeq = 0;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onChanged);
  }

  void _onChanged() {
    if (widget.state.seq == _shownSeq) return;
    _shownSeq = widget.state.seq;
    _timer?.cancel();
    _controller.forward(from: 0);
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.state.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MiuixColors colors = MiuixTheme.of(context).colors;
    return Positioned(
      left: 24,
      right: 24,
      // 悬浮于液态玻璃底栏上方
      bottom: 116,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: Center(
              // 透明 Material 提供 DefaultTextStyle，避免文字黄色下划线
              child: Material(
                type: MaterialType.transparency,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 360),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      color: colors.surface.withValues(alpha: 0.72),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          // 应用 logo
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.fact_check_rounded,
                              size: 19,
                              color: colors.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            // liveRegion：提示出现时无障碍服务会主动播报
                            child: Semantics(
                              container: true,
                              liveRegion: true,
                              label: widget.state.message,
                              child: MiuixText(
                                widget.state.message,
                                fontSize: 14,
                                // Toast 挂在 MaterialApp 顶层，无 MiuixSurface
                                // 注入内容色，必须显式指定，否则夜间模式下
                                // MiuixContentColor 回退为黑色导致深底黑字。
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
