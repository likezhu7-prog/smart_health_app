import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAlreadyLoggedIn();
  }

  Future<void> _checkAlreadyLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt("patient_id");

    if (id != null && mounted) {
      Navigator.pushReplacementNamed(context, "/dashboard");
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() => _error = "Please enter your email");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // 💡 仅保留核心数据映射逻辑
    int? targetId;
    switch (email) {
      case "njones@hotmail.com": targetId = 1; break;
      case "craig39@boyer.com": targetId = 2; break;
      case "amy61@hotmail.com": targetId = 3; break;
      case "kthomas@hotmail.com": targetId = 4; break;
      case "lisalawson@walker.com": targetId = 5; break;
      case "cassandrawalker@hotmail.com": targetId = 6; break;
      case "pperez@yahoo.com": targetId = 7; break;
      case "stevennewton@hall.net": targetId = 8; break;
      case "elizabeth67@simmons.com": targetId = 9; break;
      case "ajones@hotmail.com": targetId = 10; break;
      case "jgreen@gmail.com": targetId = 20; break;
      default: targetId = null;
    }

    await Future.delayed(const Duration(milliseconds: 500));

    if (targetId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt("patient_id", targetId);
      final username = email.contains('@') ? email.split('@').first : email;
      await prefs.setString("patient_username", username);

      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.pushReplacementNamed(context, "/dashboard");
    } else {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Login failed. Email not found.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6), // 原来的浅灰色背景
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 原来的标题
                    Text(
                      "Smart Health Login",
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    // 原来的输入框样式
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email Address",
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),

                    const SizedBox(height: 20),

                    // 原来的按钮样式
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _handleLogin,
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text("Login"),
                      ),
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}