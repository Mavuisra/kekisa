library;

import 'package:flutter/material.dart';

import '../../../core/business/business_category_profile.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../core/i18n/app_i18n.dart';
import '../../../core/i18n/locale_controller.dart';
import '../data/django_auth_service.dart';
import 'auth_router.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _bgColor = Color(0xFF035D8A);
  static const _accentError = Color(0xFFFECACA);
  static const _whiteMuted = Color(0xB3FFFFFF);
  static const _totalPages = 6;

  final _authService = djangoAuthService;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _companyTradeNameController = TextEditingController();
  final _legalFormController = TextEditingController();
  final _rccmController = TextEditingController();
  final _idnatController = TextEditingController();
  final _nifController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  final _companyCountryController = TextEditingController(text: 'RDC');
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

  String _selectedCategory = BusinessCategoryProfiles.boutique.key;
  String _selectedLanguage = 'fr';
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedCommune;
  String? _selectedQuarter;
  int _currentPage = 0;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

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
    final code = LocaleController.instance.locale.languageCode;
    _selectedLanguage = code == 'ln' ? 'ln' : 'fr';
    _selectedProvince = 'Kinshasa';
    _selectedCity = 'Kinshasa';
    _syncAddressControllersFromSelection();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _fullNameController.dispose();
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

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: _whiteMuted),
      hintStyle: const TextStyle(color: Color(0x99FFFFFF)),
      prefixIcon: icon == null ? null : Icon(icon, color: _whiteMuted),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white, width: 1.3),
      ),
    );
  }

  bool _validateCurrentStep() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();
    final companyName = _companyNameController.text.trim();

    if (_currentPage == 2) {
      if (username.isEmpty || password.isEmpty || phone.isEmpty) {
        setState(
          () => _error =
              'Renseignez identifiant, mot de passe et numéro de téléphone.',
        );
        return false;
      }
      if (password.length < 6) {
        setState(
          () => _error = 'Le mot de passe doit contenir au moins 6 caractères.',
        );
        return false;
      }
    }

    if (_currentPage == 4) {
      if (companyName.isEmpty) {
        setState(
          () => _error = 'La raison sociale de l\'entreprise est obligatoire.',
        );
        return false;
      }
    }

    setState(() => _error = null);
    return true;
  }

  Future<void> _goToPage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _totalPages) return;
    setState(() {
      _currentPage = pageIndex;
      _error = null;
    });
  }

  Future<void> _nextStep() async {
    if (_currentPage == 0) {
      await _goToPage(1);
      return;
    }
    if (!_validateCurrentStep()) return;
    if (_currentPage < _totalPages - 1) {
      await _goToPage(_currentPage + 1);
    }
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();
    final fullName = _fullNameController.text.trim();
    final companyName = _companyNameController.text.trim();
    final companyProvince = _companyProvinceController.text.trim();
    final companyCity = _companyCityController.text.trim();

    if (!_validateCurrentStep()) return;
    if (username.isEmpty || password.isEmpty || phone.isEmpty) {
      setState(
        () => _error =
            'Renseignez identifiant, mot de passe et numéro de téléphone.',
      );
      return;
    }
    if (companyName.isEmpty) {
      setState(() => _error = 'Renseignez la raison sociale de l\'entreprise.');
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await _authService.register(
        username: username,
        password: password,
        phone: phone,
        businessCategory: _selectedCategory,
        companyName: companyName,
        companyTradeName: _companyTradeNameController.text.trim(),
        legalForm: _legalFormController.text.trim(),
        rccm: _rccmController.text.trim(),
        idnat: _idnatController.text.trim(),
        nif: _nifController.text.trim(),
        companyEmail: _companyEmailController.text.trim(),
        companyPhone: _companyPhoneController.text.trim(),
        companyCountry: _companyCountryController.text.trim().isEmpty
            ? 'RDC'
            : _companyCountryController.text.trim(),
        companyProvince: companyProvince,
        companyCity: companyCity,
        companyCommune: _companyCommuneController.text.trim(),
        companyQuarter: _companyQuarterController.text.trim(),
        companyAvenue: _companyAvenueController.text.trim(),
        companyNumber: _companyNumberController.text.trim(),
        fullName: fullName.isEmpty ? null : fullName,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthRouter()),
        (_) => false,
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  List<String> get _availableCities {
    final province = _selectedProvince;
    if (province == null) return const <String>[];
    return _citiesByProvince[province] ?? const <String>[];
  }

  List<String> get _availableCommunes {
    final city = _selectedCity;
    if (city != 'Kinshasa') return const <String>[];
    final seen = <String>{};
    final keys =
        _kinshasaQuartersByCommune.keys
            .map(_normalizeLocationKey)
            .where((e) => e.isNotEmpty && seen.add(e))
            .toList()
          ..sort();
    return keys;
  }

  List<String> get _availableQuarters {
    final commune = _selectedCommune;
    if (commune == null) return const <String>[];
    List<String> raw = const <String>[];
    for (final entry in _kinshasaQuartersByCommune.entries) {
      if (_normalizeLocationKey(entry.key) == _normalizeLocationKey(commune)) {
        raw = entry.value;
        break;
      }
    }
    final seen = <String>{};
    return raw
        .map(_normalizeLocationKey)
        .where((e) => e.isNotEmpty && seen.add(e))
        .toList();
  }

  void _syncAddressControllersFromSelection() {
    _companyProvinceController.text = _selectedProvince ?? '';
    _companyCityController.text = _selectedCity ?? '';
    _companyCommuneController.text = _selectedCommune ?? '';
    _companyQuarterController.text = _selectedQuarter ?? '';
  }

  Widget _buildStepContainer({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: _whiteMuted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroPage() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/register_intro.png',
                  fit: BoxFit.cover,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _bgColor.withValues(alpha: 0.18),
                        _bgColor.withValues(alpha: 0.62),
                        _bgColor,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Créez votre espace en quelques étapes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Configurez votre activité, puis accédez à une expérience fluide pour gérer votre entreprise.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _whiteMuted,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _nextStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _bgColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          context.tr('Commencer'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        context.tr('J\'ai déjà un compte'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationBar() {
    final isLast = _currentPage == _totalPages - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: _accentError, fontSize: 13),
              ),
            ),
          Row(
            children: [
              if (_currentPage > 1)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading
                        ? null
                        : () => _goToPage(_currentPage - 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                    child: Text(context.tr('Retour')),
                  ),
                ),
              if (_currentPage > 1) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : (isLast ? _submit : _nextStep),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _bgColor,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _bgColor,
                          ),
                        )
                      : Text(
                          isLast
                              ? context.tr('Créer un compte')
                              : context.tr('Suivant'),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: Text(
              context.tr('J\'ai déjà un compte'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryProfile = BusinessCategoryProfiles.fromKey(_selectedCategory);
    final progress = (_currentPage <= 0)
        ? 0.0
        : (_currentPage / (_totalPages - 1));

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            if (_currentPage > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _loading
                          ? null
                          : () {
                              if (_currentPage > 1) {
                                _goToPage(_currentPage - 1);
                              } else {
                                _goToPage(0);
                              }
                            },
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 7,
                          backgroundColor: Colors.white.withValues(alpha: 0.20),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${context.tr('Étape')} $_currentPage/${_totalPages - 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentPage),
                  child: [
                    _buildIntroPage(),
                    _buildStepContainer(
                      title: context.tr('Langue'),
                      subtitle:
                          'Choisissez la langue principale de votre espace.',
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _selectedLanguage,
                          dropdownColor: _bgColor.withValues(alpha: 0.95),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: context.tr('Langue de l’application'),
                            icon: Icons.language_outlined,
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
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _selectedLanguage = value);
                            await LocaleController.instance.setLanguageCode(
                              value,
                            );
                          },
                        ),
                      ],
                    ),
                    _buildStepContainer(
                      title: 'Compte utilisateur',
                      subtitle: 'Commençons par vos accès principaux.',
                      children: [
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                          decoration: _inputDecoration(
                            label: 'Identifiant',
                            hint: 'ex: vendeur1',
                            icon: Icons.person_outline_rounded,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) =>
                              FocusScope.of(context).nextFocus(),
                          decoration: _inputDecoration(
                            label: 'Mot de passe (min. 6 caractères)',
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: _whiteMuted,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _phoneController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          decoration: _inputDecoration(
                            label: 'Numéro de téléphone',
                            hint: '+243 97 000 00 00',
                            icon: Icons.phone_outlined,
                          ),
                        ),
                      ],
                    ),
                    _buildStepContainer(
                      title: 'Profil d’activité',
                      subtitle:
                          'Choisissez votre secteur pour adapter l’interface.',
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          dropdownColor: _bgColor.withValues(alpha: 0.95),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Catégorie de compte',
                            icon: Icons.category_outlined,
                          ),
                          items: BusinessCategoryProfiles.all
                              .map(
                                (profile) => DropdownMenuItem<String>(
                                  value: profile.key,
                                  child: Text(profile.label),
                                ),
                              )
                              .toList(),
                          onChanged: _loading
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() => _selectedCategory = value);
                                },
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white.withValues(alpha: 0.10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.insights_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  categoryProfile.subtitle,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _fullNameController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          textInputAction: TextInputAction.done,
                          decoration: _inputDecoration(
                            label: 'Nom complet (optionnel)',
                            hint: 'ex: Jean Kabongo',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                      ],
                    ),
                    _buildStepContainer(
                      title: 'Informations entreprise',
                      subtitle:
                          'Ajoutez les détails administratifs de votre structure.',
                      children: [
                        TextField(
                          controller: _companyNameController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'Raison sociale *',
                            hint: 'ex: TEKISA SARL',
                            icon: Icons.business_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _companyTradeNameController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'Nom commercial',
                            hint: 'ex: Boutique Horizon',
                            icon: Icons.storefront_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _legalFormController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'Forme juridique',
                            hint: 'ex: SARL, SA, Etablissement',
                            icon: Icons.gavel_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _rccmController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'RCCM',
                            hint: 'ex: CD/KIN/RCCM/24-B-1234',
                            icon: Icons.article_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _idnatController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'ID.NAT',
                            hint: 'ex: 01-A12345N',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nifController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'NIF',
                            hint: 'ex: A1234567Z',
                            icon: Icons.numbers_outlined,
                          ),
                        ),
                      ],
                    ),
                    _buildStepContainer(
                      title: 'Contact et adresse',
                      subtitle:
                          'Finalisez les coordonnées de votre entreprise.',
                      children: [
                        TextField(
                          controller: _companyEmailController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _inputDecoration(
                            label: 'Email entreprise',
                            hint: 'contact@entreprise.cd',
                            icon: Icons.email_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _companyPhoneController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          keyboardType: TextInputType.phone,
                          decoration: _inputDecoration(
                            label: 'Téléphone entreprise',
                            hint: '+243...',
                            icon: Icons.phone_in_talk_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _companyCountryController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'Pays',
                            icon: Icons.flag_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedProvince,
                            _provinces,
                          ),
                          dropdownColor: _bgColor.withValues(alpha: 0.95),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Province',
                            icon: Icons.location_city_outlined,
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedCity,
                            _availableCities,
                          ),
                          dropdownColor: _bgColor.withValues(alpha: 0.95),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Ville',
                            icon: Icons.location_on_outlined,
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedCommune,
                            _availableCommunes,
                          ),
                          dropdownColor: _bgColor.withValues(alpha: 0.95),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Commune',
                            icon: Icons.map_outlined,
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _matchDropdownValue(
                            _selectedQuarter,
                            _availableQuarters,
                          ),
                          dropdownColor: _bgColor.withValues(alpha: 0.95),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Quartier',
                            icon: Icons.home_work_outlined,
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
                        const SizedBox(height: 12),
                        TextField(
                          controller: _companyAvenueController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          decoration: _inputDecoration(
                            label: 'Avenue',
                            icon: Icons.alt_route_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _companyNumberController,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: Colors.white,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: _inputDecoration(
                            label: 'Numéro parcelle / porte',
                            icon: Icons.pin_outlined,
                          ),
                        ),
                      ],
                    ),
                  ][_currentPage],
                ),
              ),
            ),
            if (_currentPage > 0) _buildNavigationBar(),
          ],
        ),
      ),
    );
  }
}
