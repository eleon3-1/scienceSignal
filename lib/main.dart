import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'quizScreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final email = TextEditingController();
  final password = TextEditingController();
  final authChanges = FirebaseAuth.instance.authStateChanges();

  String error = '';
  bool loading = false;

  Future<void> signIn() async {
    if (loading) return;

    setState(() {
      error = '';
      loading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );

      if (mounted) password.clear();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message ?? 'Sign n failed.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Science Signal',
      home: Scaffold(
        appBar: AppBar(title: const Text('Science Signal')),
        body: StreamBuilder<User?>(
          stream: authChanges,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const Center(child: Text('Authentication error'));
            }

            final user = snapshot.data;

            if (user != null) {
              return QuizScreen(key: ValueKey(user.uid), user: user);
            }

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: email,
                  enabled: !loading,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Your email'),
                ),
                TextField(
                  controller: password,
                  enabled: !loading,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'your password'),
                ),
                if (error.isNotEmpty)
                  Text(error, style: const TextStyle(color: Colors.red)),
                ElevatedButton(
                  onPressed: loading ? null : signIn,
                  child: Text(loading ? 'Signing in' : 'Sign in'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
