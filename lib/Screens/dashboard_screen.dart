import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/app_theme.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString("patient_username");
    if (mounted) setState(() => _username = name);
  }

  // ── Small grid card ──────────────────────────────────────────────────────
  Widget _gridCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Grid row helper ───────────────────────────────────────────────────────
  Widget _gridRow(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  // ── Featured wide card (AI assistant) ───────────────────────────────────
  Widget _featuredCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Patient Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency_outlined),
            tooltip: "Emergency SOS",
            onPressed: () => Navigator.pushNamed(context, "/emergency"),
          ),
          IconButton(
            icon: const Icon(Icons.person_outlined),
            tooltip: "Profile",
            onPressed: () => Navigator.pushNamed(context, "/profile"),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Welcome header ──────────────────────────────────────────
            Text(
              _username != null && _username!.isNotEmpty
                  ? "Hello, $_username!"
                  : "Welcome!",
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "What would you like to check today?",
              style: TextStyle(fontSize: 14, color: AppColors.textMuted),
            ),

            const SizedBox(height: 28),

            // ══ Section 1: Health Monitoring ════════════════════════════
            _sectionHeader("Health Monitoring"),
            _gridRow(
              _gridCard(
                icon: Icons.watch_outlined,
                title: "Wearable Vitals",
                subtitle: "Steps · Calories · HR",
                onTap: () => Navigator.pushNamed(context, "/vitals"),
              ),
              _gridCard(
                icon: Icons.history,
                title: "Vitals History",
                subtitle: "Clinical records",
                onTap: () => Navigator.pushNamed(context, "/history"),
              ),
            ),
            const SizedBox(height: 14),
            _gridRow(
              _gridCard(
                icon: Icons.insights,
                title: "Health Insights",
                subtitle: "Risk analysis & alerts",
                onTap: () => Navigator.pushNamed(context, "/insights"),
              ),
              _gridCard(
                icon: Icons.trending_up,
                title: "Trend Analysis",
                subtitle: "This week vs last",
                onTap: () => Navigator.pushNamed(context, "/trends"),
              ),
            ),

            const SizedBox(height: 28),

            // ══ Section 2: Health Management ════════════════════════════
            _sectionHeader("Health Management"),
            _gridRow(
              _gridCard(
                icon: Icons.medication_outlined,
                title: "Medications",
                subtitle: "Track & manage meds",
                onTap: () => Navigator.pushNamed(context, "/medications"),
              ),
              _gridCard(
                icon: Icons.sick_outlined,
                title: "Symptom Log",
                subtitle: "Daily symptom diary",
                onTap: () => Navigator.pushNamed(context, "/symptoms"),
              ),
            ),
            const SizedBox(height: 14),
            _gridRow(
              _gridCard(
                icon: Icons.flag_outlined,
                title: "Health Goals",
                subtitle: "Steps · Sleep · Calories",
                onTap: () => Navigator.pushNamed(context, "/goals"),
              ),
              _gridCard(
                icon: Icons.monitor_weight_outlined,
                title: "BMI Calculator",
                subtitle: "Check your BMI",
                onTap: () => Navigator.pushNamed(context, "/bmi"),
              ),
            ),

            const SizedBox(height: 28),

            // ══ Featured: AI Health Assistant ════════════════════════════
            _featuredCard(
              icon: Icons.smart_toy_outlined,
              title: "AI Health Assistant",
              subtitle: "Ask Gemini AI about your health data",
              onTap: () => Navigator.pushNamed(context, "/assistant"),
            ),

            const SizedBox(height: 20),

            // ── Settings link ─────────────────────────────────────────
            InkWell(
              onTap: () => Navigator.pushNamed(context, "/settings"),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
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
                child: const Row(
                  children: [
                    Icon(Icons.settings_outlined, size: 22, color: AppColors.primary),
                    SizedBox(width: 12),
                    Text("Settings",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark)),
                    Spacer(),
                    Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
