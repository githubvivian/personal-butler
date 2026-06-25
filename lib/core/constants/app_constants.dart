import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const background = Color(0xFFF1F5F9);
  static const card = Colors.white;
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const accentOrange = Color(0xFFF97316);
  static const accentGreen = Color(0xFF22C55E);
  static const accentPurple = Color(0xFF8B5CF6);
  static const accentPink = Color(0xFFEC4899);
  static const accentTeal = Color(0xFF14B8A6);
  static const danger = Color(0xFFEF4444);
  static const border = Color(0xFFE2E8F0);

  static Color forItemType(String type) {
    switch (type) {
      case 'meeting':
        return primary;
      case 'reimbursement':
        return accentOrange;
      case 'review':
        return accentPurple;
      case 'task':
        return accentTeal;
      case 'birthday':
        return accentPink;
      case 'family':
        return accentGreen;
      default:
        return textSecondary;
    }
  }

  static Color forOwner(String owner) {
    switch (owner) {
      case 'beibei':
        return accentPink;
      case 'hetao':
        return accentOrange;
      case 'self':
        return primary;
      case 'family':
        return accentGreen;
      default:
        return textSecondary;
    }
  }
}

class AppConstants {
  static const appName = '个人管家';
  static const sessionHours = 2;
  static const dbName = 'personal_butler.db';
  static const dbVersion = 3;

  static const ownerSelf = 'self';
  static const ownerBeibei = 'beibei';
  static const ownerHetao = 'hetao';
  static const ownerFamily = 'family';

  static const owners = [
    (id: ownerSelf, label: '我'),
    (id: ownerBeibei, label: '贝贝'),
    (id: ownerHetao, label: '核桃'),
    (id: ownerFamily, label: '家庭'),
  ];

  static String ownerLabel(String id) {
    return owners
        .firstWhere((o) => o.id == id, orElse: () => (id: id, label: id))
        .label;
  }

  static const itemTypes = [
    (id: 'meeting', label: '会议', icon: Icons.groups),
    (id: 'task', label: '任务', icon: Icons.task_alt),
    (id: 'reimbursement', label: '报账', icon: Icons.receipt_long),
    (id: 'review', label: '评审', icon: Icons.rate_review),
    (id: 'birthday', label: '生日', icon: Icons.cake),
    (id: 'other', label: '其他', icon: Icons.more_horiz),
  ];

  static const pendingStatuses = [
    (id: 'submitted', label: '已提交'),
    (id: 'reviewing', label: '审核中'),
    (id: 'waiting', label: '等待结果'),
    (id: 'need_action', label: '需处理'),
    (id: 'approved', label: '已通过'),
    (id: 'rejected', label: '已驳回'),
    (id: 'done', label: '已完成'),
  ];

  static const vaultCategories = [
    (id: 'website', label: '网站'),
    (id: 'app', label: 'App'),
    (id: 'email', label: '邮箱'),
  ];

  static const ideaTags = ['科研', '项目', '生活'];
}
