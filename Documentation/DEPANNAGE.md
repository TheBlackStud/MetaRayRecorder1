# Dépannage

## « Compiler IPA iPhone » n’apparaît pas sur GitHub

Vérifiez que `.github/workflows/build-ios.yml` est à la racine du dépôt, sur sa branche principale. Le dépôt ne doit pas simplement contenir le ZIP, ni un dossier parent qui englobe tout le projet. Activez GitHub Actions si la page le demande.

## Le workflow se termine en rouge

Ouvrez la première étape en échec. Les journaux sont visibles dans GitHub et, lorsque leur création a été possible, regroupés dans l’artefact `MetaRayRecorder-diagnostics`. Une erreur Swift/iOS doit être corrigée dans les sources avant de relancer. Une erreur de quota, d’autorisation, de téléchargement ou d’image macOS relève de la compilation hébergée. Ne renommez pas une archive source en `.ipa` pour contourner l’échec.

Le projet exige Xcode 26.4 minimum. Le script préfère Xcode 26.6 lorsqu’il est présent, puis cherche une autre version stable compatible. Il s’arrête si aucune n’est disponible. La sélection du simulateur est automatique parmi les iPhone installés sur le runner.

## « Aucun enregistrement à sauvegarder » / « Aucune image reçue »

Il faut voir un aperçu réel avant de toucher Enregistrer. Connectez les lunettes dans Meta AI, activez le mode développeur Meta, autorisez la caméra, ouvrez la session puis démarrez l’aperçu. Le simulateur n’a pas accès aux lunettes de l’utilisateur.

## L’application est installée mais ne s’ouvre pas

Vérifiez la confiance accordée au profil développeur dans les réglages iOS et activez le mode développeur iOS si l’installation le demande. Si la signature gratuite a expiré, re-signez le même IPA. Ne désinstallez pas l’application sans avoir exporté ses vidéos : la désinstallation peut supprimer ses données locales.

## Meta AI indique une incompatibilité ou une mise à jour

Gardez Meta AI et les lunettes à jour. Dans les réglages de MetaRay, les commandes « Mettre à jour les lunettes » et « Mettre à jour l’intégration dans les lunettes » ouvrent les flux prévus par le SDK. Le projet est prévu pour le mode développeur Meta ; les canaux de publication normaux nécessitent d’autres identifiants et autorisations.

## Le micro Bluetooth n’apparaît pas

Arrêtez la session, ouvrez Réglages dans MetaRay et recherchez les micros. Les lunettes doivent également être disponibles comme appareil audio Bluetooth. Choisissez leur nom explicitement. Ne choisissez pas le nom d’un autre casque. Le code ne remplace jamais ce port par le microphone intégré du téléphone. Filmez sans son si le port HFP des lunettes n’est pas disponible.

## L’enregistrement s’arrête quand je verrouille l’iPhone

Ce n’est plus l’arrêt volontaire prévu : la v1.1.0 conserve caméra et encodeur quand l’app passe en arrière-plan. Vérifiez que l’enregistrement démarre (REC), que le mode développeur Meta est actif et que les modes arrière-plan figurent dans Info.plist. Testez avec puis sans son. Un arrêt réel peut venir du système iOS, des lunettes, d’une rupture de transport ou de la batterie. Le code ne peut pas garantir la continuité matérielle.

## Je ne retrouve pas une vidéo

Les fichiers finalisés se trouvent dans la bibliothèque et dans Fichiers → Sur mon iPhone → MetaRay Recorder → Enregistrements. L’ajout dans Photos est une action manuelle depuis la bibliothèque. Une vidéo non finalisée lisible peut être récupérée au prochain lancement. Une coupure brutale ou un fichier illisible peut empêcher cette récupération.

## La vidéo n’est pas en 3K ou le son est décalé

Cette application enregistre le flux reçu par l’iPhone, pas la capture interne native des lunettes. Le réglage élevé demande 720 × 1280 au SDK. Les dimensions finales peuvent inclure une mise à l’échelle. Le son utilise le profil Bluetooth HFP ; sa latence par rapport au flux caméra peut varier. Aucune synchronisation parfaite n’est garantie sans essai matériel.
