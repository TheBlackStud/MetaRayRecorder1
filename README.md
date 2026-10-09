# MetaRay Recorder · v1.1.0 · iPhone personnel

Application SwiftUI utilisant le **SDK officiel Meta Wearables DAT 1.0.0**, conçue pour les Ray-Ban Meta Gen 2.

## Fonctions incluses

- Association avec Meta AI et autorisation caméra des lunettes.
- Un seul bouton **Démarrer l’enregistrement** après association ; connexion/session/caméra automatique.
- Flux vidéo brut enregistré dans un **MP4 H.264 local**. Aucun minuteur 3/5 minutes ajouté.
- **Aperçu masqué par défaut** ; afficher/masquer la vidéo ne modifie pas la capture.
- **Verrouillage de l’iPhone** sans arrêt *volontaire* du flux ni du fichier : traitements d’images déconnectés de SwiftUI, modes arrière-plan Meta configurés.
- Arrêt et sauvegarde depuis l’application, bibliothèque, partage et export vers Photos.
- Audio facultatif via microphone Bluetooth HFP explicitement sélectionné (pas de repli vers le micro de l’iPhone).
- Gestion des interruptions du flux, stockage bas et température, et recherche de MP4 récupérables après interruption.
- Projet Xcode, tests unitaires de l’encodeur et workflow GitHub Actions pour créer un IPA iPhone non signé.

## Ce qui n’est pas inclus / garanties

- **Le bouton physique de capture des Ray-Ban n’arrête pas la vidéo tierce.** L’API Meta Inputs nécessaire est expérimentale et exige une approbation en Wearables Developer Center. Le bouton Arrêter de l’application est utilisable.
- L’enregistrement écran verrouillé est supporté par le SDK selon Meta, mais reste soumis aux limitations iOS, à la mémoire, la liaison, la batterie et au firmware. **Il n’est pas garanti sans essai matériel.**
- Le flux vidéo du SDK n’est **pas le 3K natif** enregistré dans les lunettes ; résolution max demandée 720×1280, dégradation automatique possible.
- Un IPA compilé sur GitHub est **non signé**. Signature avec identifiant Apple personnel nécessaire avant installation ; renouvellement typique tous les 7 jours avec compte gratuit.
- Ces sources ne sont pas un IPA et ne peuvent pas être compilées directement avec Windows. L’archive GitHub Actions compile sur macOS.

## Installation (Windows + iPhone)

1. **Sauvegardez vos vidéos** de l’ancienne version dans Fichiers → Sur mon iPhone → MetaRay Recorder → Enregistrements avant toute réinstallation.
2. Remplacez dans votre dépôt GitHub les fichiers du projet par cette archive, en conservant le dossier caché `.github/workflows` ; le plus fiable sur Windows est GitHub Desktop.
3. Dépôt GitHub → **Actions → Compiler IPA iPhone → Run workflow**. L’étape de préparation vérifie le code et les réglages de fond, les tests iOS passent sur le simulateur, puis le programme compile pour un vrai iPhone.
4. Si l’exécution est verte : téléchargez l’artefact **MetaRayRecorder-IPA**, extrayez `MetaRayRecorder-unsigned.ipa`, signez/installez-le avec votre compte Apple via votre outil iOS compatible.
5. Activez **Developer Mode dans Meta AI**, connectez les lunettes une première fois et touchez **Démarrer l’enregistrement**. Lorsque REC démarre, verrouillez l’iPhone puis rouvrez l’application pour **Arrêter et sauvegarder**.
6. Contrôlez la durée effective et la lisibilité du MP4. Commencez par un test court écran verrouillé avant une longue prise.

Documentation complémentaire : `DEMARRER_ICI.html`, `Documentation/VALIDATION.md` et `Documentation/DEPANNAGE.md`.

## Limite de la validation fournie

Les contrôles syntaxiques, unitaires portables et vérifications de configuration peuvent être lancés sans macOS. La compilation iOS finale et l’enregistrement avec lunettes doivent être vérifiés sur GitHub Actions puis sur l’iPhone. Cette distinction est conservée explicitement.
