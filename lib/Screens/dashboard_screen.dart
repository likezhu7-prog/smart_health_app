import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vitals_screen.dart';
import 'vitals_history_screen.dart';
import '../services/fitbit_service.dart';

class PatientDashboard extends StatelessWidget {
  const PatientDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Widget _dashboardButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.purple.withOpacity(0.15),
                child: Icon(icon, size: 30, color: Colors.purple),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text("Patient Dashboard"),
        backgroundColor: Colors.purple,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("Logout"),
                    content: const Text("Are you sure you want to logout?"),
                    actions: [
                      TextButton(
                        child: const Text("Cancel"),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      TextButton(
                        child:
                            const Text("Logout", style: TextStyle(color: Colors.red)),
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ],
                  );
                },
              );

              if (confirm == true) {
                _logout(context);
              }
            },
          ),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Welcome!",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),

            const SizedBox(height: 30),

            _dashboardButton(
              context: context,
              icon: Icons.watch,
              title: "Smartwatch Vitals (Apple Health)",
              onTap: () {
                Navigator.pushNamed(context, "/vitals");
              },
            ),

            const SizedBox(height: 16),

            _dashboardButton(
              context: context,
              icon: Icons.fitness_center,
              title: "Fitbit Vitals",
              onTap: () async {
                await FitbitService.connectFitbit(context);
              },
            ),

            const SizedBox(height: 16),

            _dashboardButton(
              context: context,
              icon: Icons.history,
              title: "Vitals History",
              onTap: () {
                Navigator.pushNamed(context, "/history");
              },
            ),
          ],
        ),
      ),
    );
  }
}
