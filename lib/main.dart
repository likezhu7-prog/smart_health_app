import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/vitals_screen.dart';
import 'screens/vitals_history_screen.dart';
import 'screens/health_insights_screen.dart';
import 'screens/health_assistant_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/medication_tracker_screen.dart';
import 'screens/symptom_logger_screen.dart';
import 'screens/health_goals_screen.dart';
import 'screens/bmi_calculator_screen.dart';
import 'screens/trend_comparison_screen.dart';
import 'screens/emergency_sos_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/device_connection_screen.dart';
import 'ui/app_theme.dart';

void main() {
  runApp(const SmartHealthApp());
}

class SmartHealthApp extends StatelessWidget {
  const SmartHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Health App',
      theme: buildAppTheme(),
      routes: {
        "/": (_) => const LoginScreen(),
        "/dashboard": (_) => const PatientDashboard(),
        "/vitals": (_) => const VitalsScreen(),
        "/history": (_) => const VitalsHistoryScreen(),
        "/insights": (_) => const HealthInsightsScreen(),
        "/assistant": (_) => const HealthAssistantScreen(),
        "/profile": (_) => const ProfileScreen(),
        "/medications": (_) => const MedicationTrackerScreen(),
        "/symptoms": (_) => const SymptomLoggerScreen(),
        "/goals": (_) => const HealthGoalsScreen(),
        "/bmi": (_) => const BmiCalculatorScreen(),
        "/trends": (_) => const TrendComparisonScreen(),
        "/emergency": (_) => const EmergencySosScreen(),
        "/settings": (_) => const SettingsScreen(),
        "/devices": (_) => const DeviceConnectionScreen(),
      },
      initialRoute: "/",
    );
  }
}
