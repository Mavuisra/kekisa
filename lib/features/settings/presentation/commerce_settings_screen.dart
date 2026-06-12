library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/support/support_contact.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../data/datasources/auth_local_datasource.dart';
import '../../../data/datasources/local_auth_datasource.dart';
import '../../../data/models/user_model.dart';
import '../../auth/data/django_auth_service.dart';
import '../../auth/presentation/auth_router.dart';

class CommerceSettingsScreen extends StatefulWidget {
  const CommerceSettingsScreen({super.key});

  @override
  State<CommerceSettingsScreen> createState() => _CommerceSettingsScreenState();
}

class _CommerceSettingsScreenState extends State<CommerceSettingsScreen> {
  final _authLocal = AuthLocalDataSource();
  final _localAuth = LocalAuthDataSource();
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _companyTradeNameController = TextEditingController();
  final _legalFormController = TextEditingController();
  final _rccmController = TextEditingController();
  final _idnatController = TextEditingController();
  final _nifController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyCountryController = TextEditingController();
  final _companyProvinceController = TextEditingController();
  final _companyCityController = TextEditingController();
  final _companyCommuneController = TextEditingController();
  final _companyQuarterController = TextEditingController();
  final _companyAvenueController = TextEditingController();
  final _companyNumberController = TextEditingController();
  static const List<String> _provinces = <String>[
    'Kinshasa',
    'Kongo Central',
    'Haut-Katanga',
    'Nord-Kivu',
    'Sud-Kivu',
    'Lualaba',
    'Kasai',
    'Tshopo',
    'Maniema',
  ];
  static const Map<String, List<String>> _citiesByProvince =
      <String, List<String>>{
        'Kinshasa': <String>['Kinshasa'],
        'Kongo Central': <String>['Matadi', 'Boma', 'Mbanza-Ngungu'],
        'Haut-Katanga': <String>['Lubumbashi', 'Likasi', 'Kasumbalesa'],
        'Nord-Kivu': <String>['Goma', 'Butembo', 'Beni'],
        'Sud-Kivu': <String>['Bukavu', 'Uvira', 'Baraka'],
        'Lualaba': <String>['Kolwezi', 'Dilolo'],
        'Kasai': <String>['Tshikapa'],
        'Tshopo': <String>['Kisangani'],
        'Maniema': <String>['Kindu'],
      };
  static const Map<String, List<String>> _kinshasaQuartersByCommune =
      <String, List<String>>{
        'Gombe': <String>['Basoko', 'Commerce', 'Socimat', 'Funa'],
        'Kintambo': <String>['Kintambo Magasin', 'Lubudi', 'Haut Commandement'],
        'Ngaliema': <String>['Binza Meteo', 'Joli Parc', 'Ma Campagne', 'UPN'],
        'Lingwala': <String>['Beaux-Vents', 'Wenze'],
        'Barumbu': <String>['Sifunzo', 'Nfumu-Nsuka'],
        'Bandalungwa': <String>['Bisengo', 'Makelele', 'Lubudi'],
        'Bumbu': <String>['Mfimi', 'Lubi', 'Dipiya'],
        'Kalamu': <String>['Yolo Nord', 'Yolo Sud', 'Immo Congo'],
        'Kasa-Vubu': <String>['Onatra', 'Lwambo', 'Assossa'],
        'Kimbanseke': <String>['Mokali', 'Kingasani', 'Masina Siforco'],
        'Lemba': <String>['Righini', 'Salongo', 'Super Lemba'],
        'Limete': <String>['Industriel', 'Kingabwa', 'Résidentiel'],
        'Makala': <String>['Mabulu', 'Mabondo', 'Mbanza-Lemba'],
        'Maluku': <String>['Menkao', 'Mikonga'],
        'Masina': <String>['Petro Congo', 'Mapela', 'Sans Fil'],
        'Matete': <String>['Debonhomme', 'Mokali'],
        'Mont-Ngafula': <String>['Kimwenza', 'Masanga-Mbila', 'Cité Verte'],
        'Ndjili': <String>['Quartier 1', 'Quartier 7', 'Quartier 13'],
        'Ngaba': <String>['Mpila', 'Baobab', 'Mateba'],
        'Ngiri-Ngiri': <String>['Kato', 'Diomi'],
        'Nsele': <String>['Bibwa', 'Mikonga'],
        'Selembao': <String>['Kalunga', 'Kingu', 'Nkulu'],
      };

  UserModel? _user;
  List<UserModel> _staffUsers = const [];
  bool _loading = true;
  bool _loadingStaff = false;
  bool _saving = false;
  String _language = 'fr';
  String _timeFormat = '24h';
  String _timeZone = 'Africa/Kinshasa';
  ThemeMode _themeMode = ThemeMode.light;
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedCommune;
  String? _selectedQuarter;

  String _normalizeLocationKey(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    return v.toUpperCase();
  }

  String? _matchDropdownValue(String? value, Iterable<String> choices) {
    if (value == null) return null;
    final normalized = _normalizeLocationKey(value);
    for (final c in choices) {
      if (_normalizeLocationKey(c) == normalized) {
        return c;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _companyNameController.dispose();
    _companyTradeNameController.dispose();
    _legalFormController.dispose();
    _rccmController.dispose();
    _idnatController.dispose();
    _nifController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    _companyCountryController.dispose();
    _companyProvinceController.dispose();
    _companyCityController.dispose();
    _companyCommuneController.dispose();
    _companyQuarterController.dispose();
    _companyAvenueController.dispose();
    _companyNumberController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final user = _authLocal.getUser();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _user = user;
    _displayNameController.text = user?.displayName ?? '';
    _phoneController.text = user?.phone ?? '';
    _companyNameController.text = user?.companyName ?? '';
    _companyTradeNameController.text = user?.companyTradeName ?? '';
    _legalFormController.text = user?.legalForm ?? '';
    _rccmController.text = user?.rccm ?? '';
    _idnatController.text = user?.idnat ?? '';
    _nifController.text = user?.nif ?? '';
    _companyEmailController.text = user?.companyEmail ?? '';
    _companyPhoneController.text = user?.companyPhone ?? '';
    _companyCountryController.text = user?.companyCountry ?? '';
    _companyProvinceController.text = user?.companyProvince ?? '';
    _companyCityController.text = user?.companyCity ?? '';
    _companyCommuneController.text = user?.companyCommune ?? '';
    _companyQuarterController.text = user?.companyQuarter ?? '';
    _companyAvenueController.text = user?.companyAvenue ?? '';
    _companyNumberController.text = user?.companyNumber ?? '';
    _selectedProvince = _companyProvinceController.text.trim().isEmpty
        ? 'Kinshasa'
        : _companyProvinceController.text.trim();
    _selectedCity = _companyCityController.text.trim().isEmpty
        ? (_citiesByProvince[_selectedProvince]?.first ?? 'Kinshasa')
        : _companyCityController.text.trim();
    _selectedCommune = _companyCommuneController.text.trim().isEmpty
        ? null
        : _companyCommuneController.text.trim();
    _selectedQuarter = _companyQuarterController.text.trim().isEmpty
        ? null
        : _companyQuarterController.text.trim();
    _selectedProvince = _matchDropdownValue(_selectedProvince, _provinces);
    _selectedCity = _matchDropdownValue(_selectedCity, _availableCities);
    _selectedCommune = _matchDropdownValue(
      _selectedCommune,
      _availableCommunes,
    );
    _selectedQuarter = _matchDropdownValue(
      _selectedQuarter,
      _availableQuarters,
    );
    _syncAddressControllersFromSelection();
    setState(() {
      final rawLang = prefs.getString('app_language') ?? 'fr';
      _language = rawLang == 'ln' ? 'ln' : 'fr';
      _timeFormat = prefs.getString('app_time_format') ?? '24h';
      _timeZone = prefs.getString('app_time_zone') ?? 'Africa/Kinshasa';
      _themeMode = ThemeController.instance.themeMode;
      _loading = false;
    });
    await _loadStaffUsers();
  }

  List<String> get _availableCities {
    final province = _selectedProvince;
    if (province == null) return const <String>[];
    return _citiesByProvince[province] ?? const <String>[];
  }

  List<String> get _availableCommunes {
    final city = _selectedCity;
    if (city != 'Kinshasa') return const <String>[];
    final keys = _kinshasaQuartersByCommune.keys.toList()..sort();
    return keys;
  }

  List<String> get _availableQuarters {
    final commune = _selectedCommune;
    if (commune == null) return const <String>[];
    return _kinshasaQuartersByCommune[commune] ?? const <String>[];
  }

  void _syncAddressControllersFromSelection() {
    _companyProvinceController.text = _selectedProvince ?? '';
    _companyCityController.text = _selectedCity ?? '';
    _companyCommuneController.text = _selectedCommune ?? '';
    _companyQuarterController.text = _selectedQuarter ?? '';
  }

  bool get _isAdmin {
    final role = (_user?.role ?? '').toLowerCase();
    return role == 'admin' || role == 'super_admin' || role == 'school_admin';
  }

  String _staffRoleLabel(String role) {
    final normalized = role.toLowerCase();
    if (normalized == 'cashier' || normalized == 'caissier') return 'Caissier';
    if (normalized == 'seller' || normalized == 'vendeur') return 'Vendeur';
    if (normalized == 'admin') return 'Admin';
    return role;
  }

  Future<void> _loadStaffUsers() async {
    final current = _user;
    if (current == null || !_isAdmin) {
      if (mounted) {
        setState(() {
          _staffUsers = const [];
          _loadingStaff = false;
        });
      }
      return;
    }
    setState(() => _loadingStaff = true);
    final users = await _localAuth.listUsers(
      businessCategory: current.businessCategory,
      companyName: current.companyName,
    );
    final filtered = users.where((u) => u.id != current.id).toList();
    if (!mounted) return;
    setState(() {
      _staffUsers = filtered;
      _loadingStaff = false;
    });
  }

  Future<void> _openCreateStaffDialog() async {
    final current = _user;
    if (current == null) return;
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String role = 'cashier';
    String? errorText;

    final payload = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Text('Creer un utilisateur'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Numéro de téléphone',
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordCtrl,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: const [
                  DropdownMenuItem(value: 'cashier', child: Text('Caissier')),
                  DropdownMenuItem(value: 'seller', child: Text('Vendeur')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setModalState(() => role = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
            FilledButton(
              onPressed: () {
                final phone = phoneCtrl.text.trim();
                final displayName = nameCtrl.text.trim();
                final password = passwordCtrl.text.trim();
                if (phone.isEmpty ||
                    displayName.isEmpty ||
                    password.length < 4) {
                  setModalState(
                    () => errorText =
                        'Téléphone + nom requis, mot de passe >= 4.',
                  );
                  return;
                }
                Navigator.of(context).pop({
                  'phone': phone,
                  'password': password,
                  'displayName': displayName,
                  'role': role,
                });
              },
              child: const Text('Creer'),
            ),
          ],
        ),
      ),
    );
    phoneCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();

    if (payload == null) return;
    try {
      await djangoAuthService.createLocalStaffUser(
        phone: payload['phone']!,
        password: payload['password']!,
        role: payload['role']!,
        businessCategory: current.businessCategory ?? 'boutique',
        companyName: current.companyName ?? '',
        displayName: payload['displayName'] ?? '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Utilisateur cree avec succes.')),
      );
      await _loadStaffUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Changer le mot de passe')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: oldCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Ancien mot de passe'),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Obligatoire' : null,
              ),
              TextFormField(
                controller: newCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Nouveau mot de passe'),
                ),
                validator: (v) => (v == null || v.length < 6)
                    ? '6 caracteres minimum'
                    : null,
              ),
              TextFormField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.tr('Confirmer'),
                ),
                validator: (v) =>
                    v != newCtrl.text ? 'Ne correspond pas' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Annuler')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: Text(context.tr('Enregistrer')),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted) {
      oldCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
      return;
    }
    try {
      await djangoAuthService.changePassword(
        oldPassword: oldCtrl.text,
        newPassword: newCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe modifie.')),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      oldCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  Future<void> _logout(BuildContext context) async {
    await djangoAuthService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthRouter()),
      (_) => false,
    );
  }

  Future<void> _contactSupport() async {
    final opened = await openWhatsAppSupport();
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Impossible d\'ouvrir WhatsApp. Vérifiez votre appareil.',
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final current = _user;
    if (current == null || _saving) return;
    setState(() => _saving = true);
    final updated = UserModel(
      id: current.id,
      role: current.role,
      email: current.email,
      username: current.username,
      businessCategory: current.businessCategory,
      avatarUrl: current.avatarUrl,
      niveau: current.niveau,
      totalScore: current.totalScore,
      displayName: _displayNameController.text.trim(),
      phone: _phoneController.text.trim(),
      companyName: _companyNameController.text.trim(),
      companyTradeName: _companyTradeNameController.text.trim(),
      legalForm: _legalFormController.text.trim(),
      rccm: _rccmController.text.trim(),
      idnat: _idnatController.text.trim(),
      nif: _nifController.text.trim(),
      companyEmail: _companyEmailController.text.trim(),
      companyPhone: _companyPhoneController.text.trim(),
      companyCountry: _companyCountryController.text.trim(),
      companyProvince: _companyProvinceController.text.trim(),
      companyCity: _companyCityController.text.trim(),
      companyCommune: _companyCommuneController.text.trim(),
      companyQuarter: _companyQuarterController.text.trim(),
      companyAvenue: _companyAvenueController.text.trim(),
      companyNumber: _companyNumberController.text.trim(),
    );
    await _authLocal.setUser(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', _language);
    await LocaleController.instance.setLanguageCode(_language);
    await prefs.setString('app_time_format', _timeFormat);
    await prefs.setString('app_time_zone', _timeZone);
    if (!mounted) return;
    setState(() {
      _user = updated;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('Paramètres enregistrés.'))),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    final role = user?.role ?? 'seller';
    final category = user?.businessCategory ?? 'boutique';

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Parametres')),
        actions: [
          IconButton(
            onPressed: () => _logout(context),
            tooltip: context.tr('Se deconnecter'),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        child: Icon(Icons.person_outline_rounded),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ??
                                  user?.username ??
                                  context.tr('Utilisateur'),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${user?.phone ?? '-'}  •  $role  •  $category',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Préférences'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _language,
                        decoration: InputDecoration(
                          labelText: context.tr('Langue'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'fr',
                            child: Text(context.tr('Français')),
                          ),
                          DropdownMenuItem(
                            value: 'ln',
                            child: Text(context.tr('Lingala')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _language = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<ThemeMode>(
                        initialValue: _themeMode,
                        decoration: InputDecoration(
                          labelText: context.tr('Theme'),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Clair'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Sombre'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('Système'),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          setState(() => _themeMode = value);
                          await ThemeController.instance.setThemeMode(value);
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _timeFormat,
                        decoration: InputDecoration(
                          labelText: context.tr('Format de temps'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '24h',
                            child: Text(context.tr('24 heures')),
                          ),
                          DropdownMenuItem(
                            value: '12h',
                            child: Text(context.tr('12 heures (AM/PM)')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _timeFormat = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _timeZone,
                        decoration: InputDecoration(
                          labelText: context.tr('Fuseau horaire'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'Africa/Kinshasa',
                            child: Text(context.tr('Kinshasa (UTC+1)')),
                          ),
                          DropdownMenuItem(
                            value: 'Africa/Lubumbashi',
                            child: Text(context.tr('Lubumbashi (UTC+2)')),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _timeZone = value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Informations entreprise'),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        controller: _displayNameController,
                        label: context.tr('Nom affiché'),
                      ),
                      _field(
                        controller: _phoneController,
                        label: context.tr('Téléphone personnel'),
                        keyboardType: TextInputType.phone,
                      ),
                      _field(
                        controller: _companyNameController,
                        label: context.tr('Raison sociale'),
                      ),
                      _field(
                        controller: _companyTradeNameController,
                        label: context.tr('Nom commercial'),
                      ),
                      _field(
                        controller: _legalFormController,
                        label: context.tr('Forme juridique'),
                      ),
                      _field(
                        controller: _rccmController,
                        label: context.tr('RCCM'),
                      ),
                      _field(
                        controller: _idnatController,
                        label: context.tr('ID.NAT'),
                      ),
                      _field(
                        controller: _nifController,
                        label: context.tr('NIF'),
                      ),
                      _field(
                        controller: _companyEmailController,
                        label: context.tr('Email entreprise'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _field(
                        controller: _companyPhoneController,
                        label: context.tr('Téléphone entreprise'),
                        keyboardType: TextInputType.phone,
                      ),
                      _field(
                        controller: _companyCountryController,
                        label: context.tr('Pays'),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedProvince,
                            _provinces,
                          ),
                          decoration: InputDecoration(
                            labelText: context.tr('Province'),
                          ),
                          items: _provinces
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(p),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedProvince = value;
                              final cities = _availableCities;
                              _selectedCity = cities.isEmpty
                                  ? null
                                  : cities.first;
                              _selectedCommune = null;
                              _selectedQuarter = null;
                              _syncAddressControllersFromSelection();
                            });
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedCity,
                            _availableCities,
                          ),
                          decoration: InputDecoration(
                            labelText: context.tr('Ville'),
                          ),
                          items: _availableCities
                              .map(
                                (city) => DropdownMenuItem<String>(
                                  value: city,
                                  child: Text(city),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedCity = value;
                              _selectedCommune = null;
                              _selectedQuarter = null;
                              _syncAddressControllersFromSelection();
                            });
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedCommune,
                            _availableCommunes,
                          ),
                          decoration: InputDecoration(
                            labelText: context.tr('Commune'),
                          ),
                          items: _availableCommunes
                              .map(
                                (commune) => DropdownMenuItem<String>(
                                  value: commune,
                                  child: Text(commune),
                                ),
                              )
                              .toList(),
                          onChanged: _availableCommunes.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedCommune = value;
                                    _selectedQuarter = null;
                                    _syncAddressControllersFromSelection();
                                  });
                                },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedQuarter,
                            _availableQuarters,
                          ),
                          decoration: InputDecoration(
                            labelText: context.tr('Quartier'),
                          ),
                          items: _availableQuarters
                              .map(
                                (quarter) => DropdownMenuItem<String>(
                                  value: quarter,
                                  child: Text(quarter),
                                ),
                              )
                              .toList(),
                          onChanged: _availableQuarters.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedQuarter = value;
                                    _syncAddressControllersFromSelection();
                                  });
                                },
                        ),
                      ),
                      _field(
                        controller: _companyAvenueController,
                        label: context.tr('Avenue'),
                      ),
                      _field(
                        controller: _companyNumberController,
                        label: context.tr('Numéro parcelle / porte'),
                      ),
                    ],
                  ),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Gestion des utilisateurs',
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _openCreateStaffDialog,
                              icon: const Icon(Icons.person_add_alt_rounded),
                              label: const Text('Ajouter'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_loadingStaff)
                          const Center(child: CircularProgressIndicator())
                        else if (_staffUsers.isEmpty)
                          const Text(
                            'Aucun utilisateur secondaire. Creez un caissier ou un vendeur.',
                          )
                        else
                          ..._staffUsers.map(
                            (u) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: theme.dividerColor),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person_outline_rounded),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (u.displayName ?? u.phone ?? '-')
                                              .trim(),
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                          '${u.phone ?? '-'} • ${_staffRoleLabel(u.role)}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ListTile(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  tileColor: theme.colorScheme.surface,
                  leading: const Icon(Icons.security_rounded),
                  title: Text(context.tr('Securite du compte')),
                  subtitle: Text(
                    context.tr('Mot de passe et sessions actives'),
                  ),
                  onTap: _changePassword,
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  tileColor: theme.colorScheme.surface,
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(context.tr('A propos')),
                  subtitle: const Text('TEKISA v1.0.0'),
                  onTap: () {},
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('Enregistrer les modifications')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _contactSupport,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Contacter le support WhatsApp'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
