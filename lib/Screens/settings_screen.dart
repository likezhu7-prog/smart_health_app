import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../ui/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = false;
  String _email = "";
  int? _patientId;
  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _load();
    _initNotifications();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawId = prefs.get("patient_id");
    _patientId = int.tryParse(rawId?.toString() ?? '');
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool("notifications_enabled_$_patientId") ?? false;
        _email = prefs.getString("patient_email") ?? "";
      });
    }
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _notifPlugin.initialize(settings);
  }

  Future<void> _toggleNotifications(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("notifications_enabled_$_patientId", val);
    setState(() => _notificationsEnabled = val);

    if (val) {
      await _scheduleDaily9am();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Daily reminders enabled at 9:00 AM")),
        );
      }
    } else {
      await _notifPlugin.cancelAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Notifications disabled")),
        );
      }
    }
  }

  Future<void> _scheduleDaily9am() async {
    const androidDetails = AndroidNotificationDetails(
      'health_reminder',
      'Daily Health Reminder',
      channelDescription: 'Reminds you to check your health metrics',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    // Show an immediate notification as a demo (daily scheduling requires timezone package)
    await _notifPlugin.show(
      0,
      'Health Check Reminder',
      'Time to review your health metrics for the day!',
      details,
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color iconColor = AppColors.primary,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted))
            : null,
        trailing: trailing ?? (onTap != null
            ? const Icon(Icons.chevron_right, color: AppColors.textMuted)
            : null),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("Settings",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.settings_outlined, size: 48, color: Colors.white54),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Account ──────────────────────────────────
                  _sectionHeader("Account"),
                  _settingsTile(
                    icon: Icons.person_outlined,
                    title: "Profile",
                    subtitle: _email.isNotEmpty ? _email : null,
                    onTap: () => Navigator.pushNamed(context, "/profile"),
                  ),

                  // ── Notifications ─────────────────────────────
                  _sectionHeader("Notifications"),
                  _settingsTile(
                    icon: Icons.notifications_outlined,
                    title: "Daily Health Reminders",
                    subtitle: "9:00 AM reminder to check vitals",
                    trailing: Switch(
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                      activeColor: AppColors.primary,
                    ),
                  ),

                  // ── Emergency ─────────────────────────────────
                  _sectionHeader("Emergency"),
                  _settingsTile(
                    icon: Icons.emergency_outlined,
                    title: "Emergency SOS Card",
                    subtitle: "Blood type, allergies, contact",
                    iconColor: Colors.red.shade600,
                    onTap: () => Navigator.pushNamed(context, "/emergency"),
                  ),

                  // ── About ─────────────────────────────────────
                  _sectionHeader("About"),
                  _settingsTile(
                    icon: Icons.info_outline,
                    title: "App Version",
                    subtitle: "1.0.0",
                    trailing: const SizedBox.shrink(),
                  ),
                  _settingsTile(
                    icon: Icons.health_and_safety_outlined,
                    title: "Smart Health App",
                    subtitle: "AI-powered patient monitoring",
                    trailing: const SizedBox.shrink(),
                  ),

                  // ── Danger Zone ───────────────────────────────
                  _sectionHeader("Danger Zone"),
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.logout, size: 20, color: Colors.red.shade700),
                      ),
                      title: Text("Logout",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700)),
                      subtitle: const Text("Clear all data and return to login",
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      trailing: Icon(Icons.chevron_right, color: Colors.red.shade300),
                      onTap: () => _logout(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
