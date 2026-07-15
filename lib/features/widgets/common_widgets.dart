import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? accentColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
    if (accentColor == null) {
      return onTap == null
          ? card
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: card,
            );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Padding(padding: const EdgeInsets.only(left: 4), child: card),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class OwnerChip extends StatelessWidget {
  final String ownerId;
  const OwnerChip({super.key, required this.ownerId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.forOwner(ownerId).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppConstants.ownerLabel(ownerId),
        style: TextStyle(
          fontSize: 12,
          color: AppColors.forOwner(ownerId),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ConfirmDeleteDialog extends StatelessWidget {
  final String title;
  final String message;
  final bool showHardDelete;

  const ConfirmDeleteDialog({
    super.key,
    required this.title,
    required this.message,
    this.showHardDelete = true,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String message,
    bool showHardDelete = true,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ConfirmDeleteDialog(
        title: title,
        message: message,
        showHardDelete: showHardDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'soft'),
          child: const Text('移入已删除'),
        ),
        if (showHardDelete)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, 'hard'),
            child: const Text('彻底删除'),
          ),
      ],
    );
  }
}

Future<void> snack(BuildContext context, String msg) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
