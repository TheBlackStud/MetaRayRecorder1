# Enregistrement avec iPhone verrouillé — intégration v1.1.0

Le flux reçu de Meta est envoyé à l’encodeur indépendamment de `UIImage` et de SwiftUI.

- `StreamActivityClock` suit les frames reçues, même quand l’aperçu est arrêté.
- `enteredBackground()` masque uniquement l’aperçu, sans `stopAll()`.
- `requestRecording()` lance session, flux et capture depuis un bouton après association.
- L’aperçu est désactivé par défaut ; possibilité de l’activer depuis l’interface.
- `UIBackgroundModes` inclut `processing`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory`, `audio`.
- Le contrôle du bouton physique Ray-Ban n’est pas implémenté : Inputs requiert une autorisation Meta et reste expérimental.

**Important** : Meta annonce que les sampleBuffers peuvent continuer écran verrouillé (discussion officielle #13). Cela ne garantit pas qu’iOS ne suspende jamais l’app. Test matériel obligatoire pour vérifier la durée réellement sauvegardée.
