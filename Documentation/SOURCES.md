# Sources techniques consultées

Vérification documentaire : 9 octobre 2026. Les interfaces des plateformes et leurs conditions peuvent évoluer. Le projet fixe la dépendance Meta à **1.0.0**, au lieu d’utiliser une branche mouvante.

## SDK Meta : sources du fournisseur

- Dépôt et conditions : https://github.com/facebook/meta-wearables-dat-ios
- Exemple CameraAccess, prérequis et mode développeur : https://github.com/facebook/meta-wearables-dat-ios/blob/main/samples/CameraAccess/README.md
- Manifeste du paquet fixé à 1.0.0 : https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.0/Package.swift
- Interface publiée de MWDATCore 1.0.0 : https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.0/MWDATCore.xcframework/ios-arm64/MWDATCore.framework/Modules/MWDATCore.swiftmodule/arm64-apple-ios.swiftinterface
- Interface publiée de MWDATCamera 1.0.0 : https://github.com/facebook/meta-wearables-dat-ios/blob/1.0.0/MWDATCamera.xcframework/ios-arm64/MWDATCamera.framework/Modules/MWDATCamera.swiftmodule/arm64-apple-ios.swiftinterface
- Configuration du SDK, Info.plist et permissions : https://github.com/facebook/meta-wearables-dat-ios/blob/main/plugins/mwdat-ios/skills/getting-started/SKILL.md
- Flux caméra, codecs et résolutions : https://github.com/facebook/meta-wearables-dat-ios/blob/main/plugins/mwdat-ios/skills/camera-streaming/SKILL.md
- Centre développeur : https://wearables.developer.meta.com/

Le projet utilise les signatures publiques `Wearables.configure`, `startRegistration`, `handleUrl`, `createSession`, `DeviceSession.addCamera`, `Stream.start`, `videoFramePublisher` et `VideoFrame.sampleBuffer`. Il ne prétend pas modifier la durée de capture native du firmware.

## Apple : compte et outils

- Compte personnel, limites et validité des profils : https://developer.apple.com/help/account/basics/about-your-developer-account
- Configuration requise pour Xcode : https://developer.apple.com/xcode/system-requirements
- Mode développeur iPhone : https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device
- AVAssetWriter : https://developer.apple.com/documentation/avfoundation/avassetwriter

## Compilation et installation

- Runners GitHub disponibles et distinction public/privé : https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- Outils de l’image macOS 26 ARM64 : https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- Sideloadly, site de l’éditeur de cet outil tiers : https://sideloadly.io/

Sideloadly annonce le support des comptes Apple gratuits et de Windows. Cette annonce ne constitue pas un test de l’application MetaRay Recorder sur le téléphone de l’utilisateur. Les actions de connexion à Apple et d’installation doivent être réalisées par l’utilisateur sur son propre ordinateur.

## Arrière-plan et boutons physiques

- Meta, réponse développeur confirmant l’accès à `VideoFrame.sampleBuffer` après verrouillage de l’iPhone : https://github.com/facebook/meta-wearables-dat-ios/discussions/13
- Intégration officielle, déclaration des `UIBackgroundModes` et transport : https://github.com/facebook/meta-wearables-dat-ios/blob/main/.github/copilot-instructions.md
- Module expérimental Inputs, approbation WDC requise pour capter les entrées physiques : https://github.com/facebook/meta-wearables-dat-ios/blob/main/CHANGELOG.md

La déclaration de modes d’arrière-plan ne garantit pas qu’iOS ne suspende jamais un processus. La validation réelle nécessite un iPhone et les lunettes.
