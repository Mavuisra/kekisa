# Tekisa (Kekisa)

Application de gestion commerciale (ventes, stock, clients, fournisseurs) — **Flutter** (mobile / web) + **API Django**.

**Dépôt :** [github.com/Mavuisra/kekisa](https://github.com/Mavuisra/kekisa)

## Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) 3.41+ (Dart 3.11+, voir `environment.sdk` dans `pubspec.yaml`)
- Python 3.12+
- (Optionnel) Redis pour Celery

## Démarrage rapide

### Backend

```bash
cd backend
python -m venv .venv
# Windows : .venv\Scripts\activate
# macOS/Linux : source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # puis éditer DJANGO_SECRET_KEY
python manage.py migrate
python manage.py runserver
```

API : `http://127.0.0.1:8000/api/v1/` — docs : `/api/schema/swagger-ui/`

### Application Flutter

À la racine du dépôt :

```bash
flutter pub get
flutter run
```

En release, l’API pointe par défaut vers `https://tekisa.pythonanywhere.com/api/v1`. Pour surcharger :

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

### APK release

```bash
flutter build apk --release
```

Sortie : `build/app/outputs/flutter-apk/app-release.apk`

## Structure du dépôt

| Dossier | Rôle |
|---------|------|
| `lib/` | Code Flutter (UI, API client) |
| `backend/` | Django REST + templates web (`/download/`, etc.) |
| `assets/` | Images et ressources partagées |
| `android/`, `ios/`, `web/` | Cibles Flutter |

## Bonnes pratiques (équipe)

- Ne pas committer `.env`, bases SQLite locales, APK/ZIP, ni les dossiers `backend/supplier_*` (uploads).
- Utiliser `backend/.env.example` comme modèle pour les variables d’environnement.
- Les médias en production vont dans `backend/media/` (servis via `PUBLIC_BASE_URL`).

## CI

GitHub Actions (`.github/workflows/ci.yml`) : `manage.py check` (Django) + `flutter analyze` sur la branche `main`.

## Licence

Projet privé — voir le dépôt distant pour les droits d’usage.
