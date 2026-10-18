// 可输入下拉栏：既可以直接键入，也可以从候选列表中选择
// 基于 MiuixTextField + 焦点下方悬浮候选列表实现，候选随输入实时过滤

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

class AutocompleteField extends StatefulWidget {
  const AutocompleteField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    this.onChanged,
    this.onSubmitted,
    this.singleLine = true,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.minLines,
    this.maxLines,
    this.insideMargin,
    this.onPickPerson,
  });

  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool singleLine;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final int? minLines;
  final int? maxLines;

  /// 透传给 MiuixTextField 的内边距（默认上下左右各 16）
  final EdgeInsets? insideMargin;

  /// 当候选项关联到某个人员时的回调（用于选择后自动带出班级/宿舍等信息）
  final void Function(String suggestion)? onPickPerson;

  @override
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void didChangeMetrics() => _scheduleRebuildOverlay();

  void _scheduleRebuildOverlay() {
    if (_overlay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlay != null) _overlay!.markNeedsBuild();
      });
    }
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _showOverlay();
    } else {
      // 延迟关闭，给候选项的点击留出时间
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        if (!_focusNode.hasFocus) _removeOverlay();
      });
    }
  }

  void _onTextChanged() {
    if (_focusNode.hasFocus) _showOverlay();
  }

  List<String> get _filtered {
    final String q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return widget.suggestions.toList();
    return widget.suggestions
        .where((String s) => s.toLowerCase().contains(q))
        .toList();
  }

  void _showOverlay() {
    if (_overlay != null) {
      _overlay!.markNeedsBuild();
      return;
    }
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, debugRequiredFor: widget).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _select(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    widget.onChanged?.call(value);
    widget.onPickPerson?.call(value);
    _focusNode.requestFocus();
  }

  Widget _buildOverlay(BuildContext context) {
    final RenderBox? box =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const SizedBox.shrink();
    final Size size = box.size;
    final List<String> items = _filtered;
    final double maxHeight = MediaQuery.of(context).size.height * 0.32;
    final MiuixColors colors = MiuixTheme.of(context).colors;

    return Stack(
      children: <Widget>[
        // 透明屏障：点击候选以外区域先收起列表
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _removeOverlay,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: Offset(0, size.height + 6),
          // 不要在 follower 外包 Align：Stack 下发的是 loose 约束，
          // Align 会撑满全屏导致候选列表相对屏幕左上角定位而非输入框下方。
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width,
                maxHeight: items.isEmpty ? 0 : maxHeight,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh.withValues(
                        alpha: 0.92,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.outline),
                    ),
                    child: items.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              // Overlay 脱离页面主题祖先，分隔线颜色需显式指定
                              color: colors.outline.withValues(alpha: 0.4),
                            ),
                            itemBuilder: (BuildContext context, int i) {
                              final String value = items[i];
                              return InkWell(
                                onTap: () {
                                  _select(value);
                                  _removeOverlay();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  // Overlay 中无 MiuixContentColor 祖先，
                                  // 不显式指定颜色时夜间主题下文字会是纯黑
                                  child: MiuixText(
                                    value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    color: colors.onBackground,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        key: _fieldKey,
        child: MiuixTextField(
          controller: widget.controller,
          focusNode: _focusNode,
          label: widget.label,
          insideMargin:
              widget.insideMargin ?? MiuixTextFieldDefaults.insideMargin,
          enabled: widget.enabled,
          singleLine: widget.singleLine,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          trailingIcon: widget.suggestions.isEmpty
              ? null
              : Icon(
                  Icons.arrow_drop_down,
                  color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
                ),
        ),
      ),
    );
  }
}
