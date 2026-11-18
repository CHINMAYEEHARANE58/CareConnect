import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../shared/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (register) {
        await auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: 'careconnect://auth-callback',
          data: {'full_name': name.text.trim()},
        );
        if (mounted) {
          showMessage(context, 'Check your email to verify your account.');
        }
      } else {
        await auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: PageFrame(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFF087E8B),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'CareConnect',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    register
                        ? 'Create your account to book care.'
                        : 'Care, on your schedule.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 28),
                  Form(
                    key: form,
                    child: Column(
                      children: [
                        if (register) ...[
                          TextFormField(
                            controller: name,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                            ),
                            validator: (v) => v == null || v.trim().length < 2
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                          ),
                          validator: (v) => v == null || !v.contains('@')
                              ? 'Enter a valid email'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (v) => v == null || v.length < 8
                              ? 'Use at least 8 characters'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: busy ? null : submit,
                          child: Text(
                            busy
                                ? 'Please wait...'
                                : register
                                ? 'Create account'
                                : 'Sign in',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => setState(() => register = !register),
                    child: Text(
                      register
                          ? 'Already have an account? Sign in'
                          : 'Create an account',
                    ),
                  ),
                  if (!register)
                    TextButton(
                      onPressed: () => context.go('/reset'),
                      child: const Text('Forgot password?'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key});
  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  final email = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reset password')),
    body: PageFrame(
      child: Column(
        children: [
          const Text('We will email you a password reset link.'),
          const SizedBox(height: 20),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await Supabase.instance.client.auth.resetPasswordForEmail(
                        email.text.trim(),
                      );
                      if (context.mounted) {
                        showMessage(
                          context,
                          'Check your email for the reset link.',
                        );
                      }
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Send reset link'),
          ),
        ],
      ),
    ),
  );
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final password = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Choose a new password')),
    body: PageFrame(
      child: Column(
        children: [
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (password.text.length < 8) {
                      showMessage(context, 'Use at least 8 characters.');
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      await Supabase.instance.client.auth.updateUser(
                        UserAttributes(password: password.text),
                      );
                      widget.onComplete();
                      if (context.mounted) context.go('/');
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Update password'),
          ),
        ],
      ),
    ),
  );
}
