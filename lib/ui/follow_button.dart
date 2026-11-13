import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../l10n/l10n_ext.dart';
import 'toast.dart';

/// 成功后由页面更新关注状态；提交期间禁用，失败保留原状态。
class FollowButton extends StatefulWidget {
  const FollowButton({
    super.key,
    required this.followed,
    required this.onChanged,
  });

  final bool followed;
  final Future<void> Function(bool) onChanged;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _pending = false;

  Future<void> _toggle() async {
    final l = AppLocalizations.of(context);
    if (!context.read<AuthController>().loggedIn) {
      showToast(context, l.loginRequired);
      return;
    }
    setState(() => _pending = true);
    try {
      await widget.onChanged(!widget.followed);
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l.actionFailed(errorText(l, e)),
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FilledButton.tonalIcon(
      onPressed: _pending ? null : _toggle,
      icon: Icon(widget.followed ? Icons.check_rounded : Icons.add_rounded),
      label: Text(widget.followed ? l.followed : l.follow),
    );
  }
}
