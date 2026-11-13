import 'package:flutter/material.dart';

import 'sheet.dart';

/// 全应用统一的弹窗：限宽居中，轻微放大淡入。
Future<T?> showKanadeDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: 0.6),
  transitionDuration: const Duration(milliseconds: 240),
  pageBuilder: (context, _, _) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(curved),
        child: child,
      ),
    );
  },
);

/// 图标、标题、说明、内容、竖排按钮，都可省略。宽窗口下最多 360 宽，不随文字拉长。
class KanadeDialog extends StatelessWidget {
  const KanadeDialog({
    super.key,
    this.icon,
    this.danger = false,
    this.title,
    this.message,
    this.content,
    this.actions = const [],
    this.animateSize = false,
  });

  final IconData? icon;

  /// 删除、退出登录这类操作：图标用警示色。
  final bool danger;
  final String? title;
  final String? message;
  final Widget? content;

  /// 一般用 [KanadeDialogAction]，主按钮放第一个。
  final List<Widget> actions;

  /// 内容会换成别的（比如更新弹窗从说明切到下载进度）时，高度平滑过渡。
  final bool animateSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, _) = sheetColors(scheme);
    final media = MediaQuery.of(context);
    final head = [
      if (icon != null) ...[
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: danger
                  ? scheme.error.withValues(alpha: 0.14)
                  : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 28,
              color: danger ? scheme.error : scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
      if (title != null)
        Text(
          title!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      if (message != null) ...[
        if (title != null) const SizedBox(height: 8),
        Text(
          message!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    ];
    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...head,
        if (content != null) ...[
          if (head.isNotEmpty) const SizedBox(height: 20),
          content!,
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          for (final (i, action) in actions.indexed) ...[
            if (i > 0) const SizedBox(height: 4),
            action,
          ],
        ] else
          const SizedBox(height: 12),
      ],
    );
    if (animateSize) {
      body = AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: body,
      );
    }
    return Center(
      child: AnimatedPadding(
        // 有输入框时键盘弹起，弹窗往上让
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              color: background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 整行宽的按钮。主按钮白底黑字（亮色模式反过来），抗色只留给播放相关；
/// 危险操作用警示色；其他是灰色文字按钮。
class KanadeDialogAction extends StatelessWidget {
  const KanadeDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (primary) {
      final style = FilledButton.styleFrom(
        backgroundColor: danger ? scheme.error : scheme.onSurface,
        foregroundColor: danger ? scheme.onError : scheme.surface,
        minimumSize: const Size.fromHeight(48),
      );
      return icon == null
          ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon, size: 20),
              label: Text(label),
            );
    }
    final style = TextButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      foregroundColor: scheme.onSurfaceVariant,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
    return icon == null
        ? TextButton(style: style, onPressed: onPressed, child: Text(label))
        : TextButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}

/// 弹窗里输入框的样式，和新建歌单的输入框一致。
InputDecoration kanadeFieldDecoration(
  BuildContext context, {
  String? hint,
  String? suffix,
  String? error,
}) {
  final scheme = Theme.of(context).colorScheme;
  final (_, fill) = sheetColors(scheme);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: scheme.outline),
  );
  return InputDecoration(
    hintText: hint,
    suffixText: suffix,
    errorText: error,
    filled: true,
    fillColor: fill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: scheme.onSurfaceVariant),
    ),
  );
}
