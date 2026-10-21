// 按需图层背景捕获：替代 flutter_miuix 自带的 MiuixLayerBackdropCapture。
//
// 自带版本在 OffsetLayer.addToScene 中每帧无条件 _scheduleCapture()：
// 即使页面静止，玻璃消费者收到快照后 markNeedsPaint → 引擎提交新帧 →
// addToScene 再次触发全屏 toImageSync → 再通知……形成永不停止的
// 60fps「快照→重绘」反馈循环，在中低端设备上表现为进入应用即严重卡顿、
// 发热掉电。这里改为：仅当捕获子树自身重绘（paint）或图层签名变化
// （滚动 / 切页 / 动画）时才更新快照；玻璃自身重绘引起的帧直接跳过。

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

/// 与 [MiuixLayerBackdropCapture] 接口一致的按需版本，喂给同一个
/// [MiuixLayerBackdrop]，玻璃消费端无需改动。
class LayerBackdropCapture extends SingleChildRenderObjectWidget {
  const LayerBackdropCapture({
    super.key,
    required this.backdrop,
    this.pixelRatio,
    required Widget super.child,
  }) : assert(
         pixelRatio == null || (pixelRatio > 0 && pixelRatio < double.infinity),
       );

  final MiuixLayerBackdrop backdrop;
  final double? pixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLayerBackdropCapture(
      backdrop: backdrop,
      devicePixelRatio:
          pixelRatio ?? MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderLayerBackdropCapture)
      ..backdrop = backdrop
      ..devicePixelRatio =
          pixelRatio ?? MediaQuery.devicePixelRatioOf(context);
  }
}

class _NotifyContentLayer extends OffsetLayer {
  _NotifyContentLayer(this.onFrame);

  /// 每帧加入 Scene 时回调；由 RenderBox 判断签名是否真的变化。
  final VoidCallback onFrame;

  @override
  void addToScene(ui.SceneBuilder builder) {
    super.addToScene(builder);
    onFrame();
  }
}

class _RenderLayerBackdropCapture extends RenderProxyBox {
  // this._field 命名形参的调用点参数名为去掉下划线的字段名
  // （backdrop / devicePixelRatio），与 miuix 自带捕获组件写法一致。
  _RenderLayerBackdropCapture({
    required this._backdrop,
    required this._devicePixelRatio,
  });

  MiuixLayerBackdrop _backdrop;
  MiuixLayerBackdrop get backdrop => _backdrop;
  set backdrop(MiuixLayerBackdrop value) {
    if (identical(_backdrop, value)) return;
    _backdrop.unregisterCapture(this);
    _backdrop = value;
    if (attached) _backdrop.registerCapture(this);
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    // DPR 变化后旧快照分辨率失效，强制重捕。
    _lastSignature = null;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _backdrop.registerCapture(this);
  }

  @override
  void detach() {
    _backdrop.unregisterCapture(this);
    super.detach();
  }

  @override
  void dispose() {
    _contentLayer.layer = null;
    super.dispose();
  }

  final LayerHandle<_NotifyContentLayer> _contentLayer =
      LayerHandle<_NotifyContentLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    _contentLayer.layer ??= _NotifyContentLayer(_onLayerFrame);
    context.pushLayer(_contentLayer.layer!, super.paint, offset);
    // 子树真的重绘了（内容 / 结构变化），本帧结束后更新快照。
    _scheduleCapture();
  }

  // ========== 按需捕获调度 ==========

  bool _captureScheduled = false;
  bool _capturing = false;
  String? _lastSignature;

  void _onLayerFrame() {
    // 没有任何 paint 发生时，本帧也可能是滚动 / 切页（仅父级变换变化），
    // 用图层签名识别；签名不变说明只是玻璃重绘带起的空帧，直接跳过，
    // 从根上打断「快照→重绘→新帧→快照」循环。
    final String signature = _layerSignature();
    if (signature != _lastSignature) _scheduleCapture();
  }

  void _scheduleCapture() {
    if (_capturing ||
        !attached ||
        _captureScheduled ||
        !hasSize ||
        size.isEmpty) {
      return;
    }
    _captureScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _captureScheduled = false;
      if (!attached || !hasSize || size.isEmpty) return;
      _capture();
    });
  }

  void _capture() {
    // 本节点是重绘边界，layer 实际为 Flutter 分配的 OffsetLayer。
    final ContainerLayer? raw = layer;
    if (raw is! OffsetLayer) return;
    final OffsetLayer owner = raw;
    _capturing = true;
    try {
      final ui.Image image = owner.toImageSync(
        Offset.zero & size,
        pixelRatio: _devicePixelRatio,
      );
      _lastSignature = _layerSignature();
      _backdrop.updateSnapshot(
        image,
        localToGlobal(Offset.zero),
        _devicePixelRatio,
      );
    } finally {
      _capturing = false;
    }
  }

  /// 遍历本重绘边界下的图层树，生成反映「结构 / 内容 / 关键几何」的签名。
  /// 仅做身份与少量标量读取，开销远小于一次全屏出图。
  String _layerSignature() {
    final ContainerLayer? owner = layer;
    if (owner == null) return '';
    final StringBuffer sb = StringBuffer();
    void walk(Layer node) {
      sb
        ..write(node.runtimeType)
        ..write('@')
        ..write(identityHashCode(node))
        ..write(';');
      if (node is OffsetLayer) {
        sb.write('o${node.offset.dx},${node.offset.dy};');
      } else if (node is TransformLayer) {
        sb.write('t${identityHashCode(node.transform)};');
      } else if (node is OpacityLayer) {
        sb.write('a${node.alpha};');
      } else if (node is PictureLayer) {
        sb.write('p${identityHashCode(node.picture)};');
      } else if (node is TextureLayer) {
        sb.write('x${node.textureId};');
      }
      if (node is ContainerLayer) {
        Layer? child = node.firstChild;
        while (child != null) {
          walk(child);
          child = child.nextSibling;
        }
      }
    }

    Layer? child = owner.firstChild;
    while (child != null) {
      walk(child);
      child = child.nextSibling;
    }
    return sb.toString();
  }
}
