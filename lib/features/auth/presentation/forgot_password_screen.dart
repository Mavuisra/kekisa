library;

import 'package:flutter/material.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/support/support_contact.dart';
import '../../auth/data/django_auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  int _step = 0;
  bool _loading = false;
  bool _obscure = true;
  bool _useEmail = true;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _contactSupport() async {
    final opened = await openWhatsAppSupport(
      message:
          'Bonjour, je n\'arrive pas a recuperer mon mot de passe sur TEKISA.',
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Impossible d\'ouvrir WhatsApp sur cet appareil.'),
      ),
    );
  }

  Future<void> _requestCode() async {
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (_useEmail && email.isEmpty) {
      setState(() => _error = 'Indiquez votre adresse email.');
      return;
    }
    if (!_useEmail && phone.isEmpty) {
      setState(() => _error = 'Indiquez votre numero de telephone.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await djangoAuthService.requestPasswordReset(
        phone: _useEmail ? null : phone,
        email: _useEmail ? email : null,
      );
      if (!mounted) return;
      setState(() => _step = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _useEmail
                ? 'Code envoye par email (gratuit).'
                : 'Code envoye par SMS.',
          ),
        ),
      );
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmReset() async {
    final phone = _phoneCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;
    if (code.isEmpty || password.length < 6) {
      setState(() => _error = 'Code et mot de passe (6+ caracteres) requis.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Les mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await djangoAuthService.confirmPasswordReset(
        phone: _useEmail ? null : phone,
        email: _useEmail ? email : null,
        code: code,
        newPassword: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe mis a jour.')),
      );
      Navigator.of(context).pop();
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublie')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _step == 0
                ? 'Recevez un code gratuit par email ou par SMS pour reinitialiser votre mot de passe.'
                : 'Saisissez le code recu et votre nouveau mot de passe.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (_step == 0) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Email'),
                  icon: Icon(Icons.email_outlined),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('SMS'),
                  icon: Icon(Icons.sms_outlined),
                ),
              ],
              selected: {_useEmail},
              onSelectionChanged: (value) {
                setState(() => _useEmail = value.first);
              },
            ),
            const SizedBox(height: 12),
            if (_useEmail)
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              )
            else
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telephone (+243...)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _requestCode,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Envoyer le code'),
            ),
          ] else ...[
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _useEmail ? 'Code email' : 'Code SMS',
                prefixIcon: Icon(
                  _useEmail ? Icons.email_outlined : Icons.sms_outlined,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _confirmReset,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reinitialiser'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'L\'email est gratuit (Gmail SMTP). Le SMS necessite un fournisseur payant.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _contactSupport,
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Contacter via WhatsApp'),
          ),
        ],
      ),
    );
  }
}
