#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null; then
  echo 'ERROR: this script requires Xcode on macOS. On Windows use the included GitHub Actions workflow.' >&2
  exit 2
fi
mkdir -p build dist
python3 Scripts/generate_project.py
xcodebuild -version
xcodebuild -resolvePackageDependencies -project MetaRayRecorder.xcodeproj -scheme MetaRayRecorder \
  -clonedSourcePackagesDirPath build/Packages 2>&1 | tee build/resolve.log
xcodebuild -project MetaRayRecorder.xcodeproj -scheme MetaRayRecorder -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/Packages CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' ONLY_ACTIVE_ARCH=NO build 2>&1 | tee build/build.log
APP='build/DerivedData/Build/Products/Release-iphoneos/MetaRayRecorder.app'
[[ -d "$APP" ]] || { echo 'ERROR: the compiled application was not produced.' >&2; exit 3; }
xcrun lipo "$APP/MetaRayRecorder" -verify_arch arm64
python3 Scripts/package_ipa.py "$APP" dist/MetaRayRecorder-unsigned.ipa
shasum -a 256 dist/MetaRayRecorder-unsigned.ipa > dist/SHA256SUMS.txt
cat > dist/INSTALLATION.txt <<'EOF'
MetaRay Recorder — IPA non signe

Ce fichier doit etre signe avec votre compte Apple avant de fonctionner sur votre iPhone.
Sur Windows : utilisez Sideloadly depuis https://sideloadly.io/ (outil tiers).
Connectez l'iPhone en USB, faites confiance au PC, selectionnez cet IPA et votre compte Apple.
Ne communiquez vos identifiants Apple ni dans le code, ni dans un depot, ni dans une conversation.
Avec un compte gratuit, la signature doit etre renouvelee tous les 7 jours.
Activez le mode developpeur iOS si demande, puis le mode developpeur dans Meta AI.
Laissez le schema d'URL metarayrecorder inchange.

Premier lancement : Connecter avec Meta AI > Demarrer l'enregistrement.
Pour le son : Reglages > Enregistrer le son Bluetooth > Rechercher > selectionner les Ray-Ban.
Une fois REC affiche, vous pouvez verrouiller l'iPhone; l'aperçu est désactivé.
L'app doit rester active selon les conditions iOS/Meta; revenez dans l'app pour arreter.
Le bouton physique des lunettes n'est pas pris en charge dans ce build.
Une perte de connexion ou suspension système peut interrompre le flux.

La compilation ne valide pas le fonctionnement avec vos lunettes ni la duree maximale reelle.
EOF
printf '\nProduced: %s\n' "$PWD/dist/MetaRayRecorder-unsigned.ipa"
