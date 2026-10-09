# État de validation du livrable

## Ce qui a été fait dans l’environnement de préparation

Environnement : Linux, Swift disponible en ligne de commande, Python 3. Aucun Xcode, SDK iOS Apple complet, iPhone ou Ray-Ban connecté n’est accessible pour compiler cette version.

| Contrôle | Résultat |
| --- | --- |
| Analyse syntaxique des 10 fichiers Swift de l’application avec `swiftc -frontend -parse` | Réussie. Ce n’est pas une compilation iOS ni une vérification complète des types. |
| Analyse syntaxique du fichier XCTest | Réussie ; les tests iOS n’ont pas été exécutés ici. |
| Compilation et exécution de `CoreChecks.swift` avec `RecordingTypes.swift` | Réussies sous Linux. |
| Tests du temps monotone, horloge du flux verrouillé, valeurs invalides et paramètres de qualité | Réussis sous Linux. |
| Contrôles de non-régression du verrouillage, de l’aperçu désactivé et de la présence du workflow | Réussis localement. |
| Génération de 1 000 noms de fichiers et vérification d’unicité | Réussie. |
| Génération du projet Xcode et validation OpenStep par `plutil` | Réussies. |
| Validation Info.plist, JSON des ressources et XML du schéma Xcode | Réussie. |
| Analyse Python, syntaxe Bash, structure YAML et blocs Bash du workflow | Réussies. |
| Contrôle de la présence des sources et références du projet | Réalisé dans le contrôle final de l’archive. |

Les tests de chronologie à 301 et 3 600 secondes injectent des horodatages simulés. Ils ne constituent pas un enregistrement de 5 minutes ou d’une heure avec les lunettes.

## Vérifications préparées mais NON exécutées ici

Le workflow `.github/workflows/build-ios.yml` prévoit une vraie compilation avec le SDK Meta et des tests sur simulateur iPhone. Il inclut des tests qui produisent un MP4 à partir d’images synthétiques, relisent la piste vidéo, vérifient une piste AAC à partir de PCM synthétique et rejettent un enregistrement sans image.

**La version précédente du projet a été compilée avec succès dans le GitHub Actions de l’utilisateur (capture de l’exécution #2).** Les modifications de la présente version v1.1.0 n’ont pas été recompilées avec Xcode et aucun IPA signé de cette version n’est fourni. Le workflow devra vérifier la compilation et les tests iOS ; des erreurs restent possibles.

L’outil d’empaquetage refuse un dossier source, une application de simulateur ou un fichier sans exécutable Mach-O ARM64. Un IPA n’est produit que par la chaîne de compilation macOS.

## Validation matérielle nécessaire

Avant un enregistrement important, il reste à vérifier sur l’iPhone et les Gen 2 concernés :

1. Signature avec le compte gratuit, installation, ouverture et retour depuis Meta AI après association.
2. Session caméra et aperçu réel ; enregistrement court sans son, lecture et export dans Photos.
3. Sélection du port HFP des lunettes ; enregistrement avec son et vérification de la provenance du micro et du décalage audio/vidéo.
4. Enregistrement dépassant 5 minutes, puis essai plus long sous surveillance de la température et de la batterie.
5. Verrouillage de l’iPhone pendant une vidéo de 2–5 min, puis lecture du MP4, vérification de sa durée et de son contenu.
6. Arrêt manuel, rupture Bluetooth, appel entrant et retour depuis l’arrière-plan ; vérification des fichiers conservés.
7. Renouvellement de signature sans désinstaller l’application ni perdre ses vidéos.

La durée maximale réelle, l’autonomie, la stabilité et la synchronisation audio/vidéo ne sont pas annoncées comme garanties.
