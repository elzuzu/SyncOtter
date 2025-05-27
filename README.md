# 🦦 SyncOtter - Synchronisation Ultra-Légère

Outil de synchronisation **ultra-optimisé** pour lancement **quasi-instantané** depuis un partage réseau.

Cette version repose uniquement sur l'application Electron et la ligne de commande. Les anciennes librairies expérimentales ont été retirées du dépôt.

## ✨ **Nouvelles Fonctionnalités Auto-Magiques :**

### 🔄 **Gestion Processus Intelligente :**
- **Détection automatique** des instances déjà ouvertes
- **Kill automatique** des processus existants (avec message)
- **Instance unique** garantie (pas de doublons)

### 📁 **Création Auto des Répertoires :**
- **Répertoire cible** créé automatiquement s'il manque
- **Vérification source** avant démarrage
- **Messages informatifs** pour chaque étape

### ⚙️ **Configuration Externe (NOUVEAU) :**
- **config.json externe** à l'exe (pas intégré dans la compilation)
- **Modification sans recompilation** !
- **Déploiement flexible** avec différentes configs

### 🎨 **Interface Améliorée :**
- **Messages colorés** selon le statut (succès/warning/erreur)
- **Animation pulse** pour les warnings
- **Feedback visuel** en temps réel

## 🚀 Guide de Démarrage Rapide

### **Première utilisation :**
```powershell
# 1. Installer les dépendances
npm install

# 2. Créer votre configuration
node config-generator.js

# 3. Tester en mode développement
npm start

# 4. Compiler l'exe ultra-léger
.\build-app.ps1

# 5. Déployer sur votre share/répertoire
.\deploy-enterprise.ps1 -DestinationPath "\\server\tools\SyncOtter"
```

### Compilation express :
```powershell
# Build ULTRA-LÉGER (recommandé pour share)
npm run build-ultra

# Build portable léger  
npm run build-portable

# Test développement
npm start
```

### Déploiement avec config personnalisé :
```powershell
# Déploiement simple
.\deploy-enterprise.ps1 -DestinationPath "\\server\tools\SyncOtter"

# Déploiement avec config personnalisé
.\deploy-enterprise.ps1 -DestinationPath "C:\Tools\MySync" `
             -SourceDir "\\server\releases\latest" `
             -TargetDir "C:\Apps\MyApp" `
             -AppToLaunch "C:\Apps\MyApp\app.exe" `
             -AppName "Mon Application CRM" `
             -AppDescription "Version depuis build server"
```

### Lancement optimisé :
```powershell
# Lancement direct (gestion auto des processus)
./SyncOtter-Ultra.exe

# Depuis share réseau (copie automatique)
\\server\tools\SyncOtter\SyncOtter-Ultra.exe
```

## ⚡ Optimisations Performance

### 🎯 Exe ultra-léger :
- **Compression maximale** (tous niveaux)
- **Portable** (pas d'installation)
- **Dépendances minimales** (fs-extra uniquement)
- **Démarrage immédiat** (pas d'attente splash)
- **Configuration externe** (pas intégrée dans l'exe)
- **~15-25 MB** au lieu de 100+ MB standard

### 🌐 Share réseau :
- **Copie temporaire** automatique pour accélération
- **Nettoyage auto** après utilisation  
- **Lancement quasi-instantané** même sur réseau lent
- **Détection latence/bande passante** et ajustement dynamique
- **Transferts intelligents (compression, chunk, parallèle)**
- **Reprise sur erreur avec vérification d'intégrité**
- **Cache réseau local pour synchronisation différentielle**

## ⚙️ Configuration (config.json)

**Important** : Le fichier `config.json` doit être placé **à côté de l'exe** (pas intégré dans la compilation).

### Configuration type :
```json
{
  "sourceDirectory": "\\\\server\\source",
  "targetDirectory": "C:\\Local\\Target", 
  "excludeDirectories": [".git", "node_modules", ".vs", "bin", "obj"],
  "excludePatterns": ["*.tmp", "*.log", "Thumbs.db"],
  "executeAfterSync": "C:\\Local\\Target\\app.exe",
  "appName": "Mon Application",
  "appDescription": "Synchronisation et lancement automatique",
  "parallelCopies": 8
}
```

### **Avantages Configuration Externe :**
- ✅ **Modification sans recompilation**
- ✅ **Déploiement flexible** (même exe, configs différentes)
- ✅ **Facilite la maintenance** 
- ✅ **Partage de configs** entre équipes

## 🎯 Utilisation Type Share Réseau

### **Approche Simple :**
1. **Build une fois** : `.\build-app.ps1`
2. **Déployer** : `.\deploy-enterprise.ps1 -DestinationPath "\\server\tools\SyncOtter"`
3. **Lancer depuis poste** : `\\server\tools\SyncOtter\SyncOtter-*.exe`

### **Approche Multi-Configurations :**
1. **Build une fois** : `.\build-app.ps1`
2. **Déployer pour App A** : 
   ```powershell
   .\deploy-enterprise.ps1 -DestinationPath "\\server\tools\AppA" `
                -SourceDir "\\build\AppA" `
                -TargetDir "C:\Apps\AppA" `
                -AppName "Application A"
   ```
3. **Déployer pour App B** :
   ```powershell
   .\deploy-enterprise.ps1 -DestinationPath "\\server\tools\AppB" `
                -SourceDir "\\build\AppB" `
                -TargetDir "C:\Apps\AppB" `
                -AppName "Application B"
   ```

## 📊 Performance Mesurée

| Version | Taille | Lancement Local | Lancement Share | Config |
|---------|--------|----------------|----------------|---------|
| Standard | ~100MB | 3-5s | 10-15s | Intégrée |
| **Ultra** | **~20MB** | **<1s** | **2-3s** | **Externe** |

## 🔧 Scripts Disponibles

```powershell
# BUILD
.\build-app.ps1      # Ultra-léger portable
npm run build-portable   # Portable standard  
npm run build  # Installateur léger
npm start        # Mode développement

# DÉPLOIEMENT
.\deploy-enterprise.ps1 -DestinationPath "C:\Tools"  # Déploiement simple
.\deploy-enterprise.ps1 [params...]                  # Déploiement personnalisé

# LANCEMENT
SyncOtter-Ultra.exe                       # Lancement local
\\server\tools\SyncOtter\SyncOtter-Ultra.exe  # Lancement depuis share
```

### Utilisation en ligne de commande

Une version CLI est disponible dans `package-cli.json`. Elle peut être lancée directement avec Node :

```bash
node src/cli-main.js
```

Ou compilée en exécutable via `npm run build` dans ce package.

## 🎯 **Exemples Pratiques de Configuration :**

### **Déploiement Dev → Prod :**
```json
{
  "sourceDirectory": "C:\\Dev\\MonApp",
  "targetDirectory": "C:\\Deploy\\MonApp",
  "excludeDirectories": [".git", ".vs", "bin\\Debug"],
  "executeAfterSync": "C:\\Deploy\\MonApp\\start.bat",
  "appName": "MonApp Production",
  "appDescription": "Déploiement automatique v1.0",
  "parallelCopies": 8
}
```

### **Sync depuis Share Réseau :**
```json
{
  "sourceDirectory": "\\\\buildserver\\releases\\latest",
  "targetDirectory": "C:\\Apps\\MonApp",
  "excludePatterns": ["*.pdb", "*.log"],
  "executeAfterSync": "C:\\Apps\\MonApp\\app.exe",
  "appName": "Client Lourd CRM",
  "appDescription": "Version depuis build server"
}
```

### **Mode Ultra-Rapide (SSD) :**
```json
{
  "parallelCopies": 16,
  "sourceDirectory": "D:\\Source",
  "targetDirectory": "C:\\Target",
  "appName": "Application Rapide",
  "appDescription": "Sync haute performance"
}
```

## 📈 Monitoring & Analytics

- Collecte temps réel des métriques (latence, throughput, erreurs)
- Logs JSON dans le dossier `logs/` avec rotation automatique
- Rapports générés dans `reports/`
- Rapport santé système au démarrage

## 🔄 **Structure de Déploiement :**

```
\\server\tools\SyncOtter\
├── SyncOtter-1.0.0-portable.exe  # ← L'exe compilé
├── config.json                   # ← Configuration externe
└── README.txt                    # ← Instructions (optionnel)
```

## 🦦 La loutre synchronise à la vitesse de l'éclair ! ⚡✨

### **Messages de la Loutre :**
- 📄 **"Chargement config: C:\Tools\config.json"** → Config externe trouvée
- 🔄 **"Processus précédent fermé..."** → Kill automatique réussi
- 📁 **"Création du répertoire..."** → Répertoire cible créé
- ⚠️ **"Aucun fichier à synchroniser"** → Source vide
- ✅ **"X fichiers synchronisés"** → Mission accomplie !

**La loutre gère tout ! Configuration externe + gestion processus + répertoires auto = Zéro souci ! 🦦💪**

## 🚀 Build & Deploy Revolution

- `build-ultra-webpack` : packaging ultra-compact via Webpack+Brotli
- `deploy-enterprise.ps1` : déploiement automatisé avec rollback
- `config-generator.js` : génération de templates par environnement
- Mise à jour automatique pilotée par `version-manager.js`
