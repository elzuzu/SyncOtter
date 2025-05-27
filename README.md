# 🦦 SyncOtter - Synchronisation Ultra-Légère

Outil de synchronisation **ultra-optimisé** pour lancement **quasi-instantané** depuis share réseau !

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
# 1. Créer votre configuration
.\setup-config.ps1

# 2. Tester en mode développement  
npm start

# 3. Compiler l'exe ultra-léger
.\build.ps1 -Type ultra

# 4. Déployer sur votre share/répertoire
.\deploy.ps1 -DestinationPath "\\server\tools\SyncOtter"
```

### Compilation express :
```powershell
# Build ULTRA-LÉGER (recommandé pour share)
.\build.ps1 -Type ultra

# Build portable léger  
.\build.ps1 -Type portable

# Test développement
.\build.ps1 -Type dev
```

### Déploiement avec config personnalisé :
```powershell
# Déploiement simple
.\deploy.ps1 -DestinationPath "\\server\tools\SyncOtter"

# Déploiement avec config personnalisé
.\deploy.ps1 -DestinationPath "C:\Tools\MySync" `
             -SourceDir "\\server\releases\latest" `
             -TargetDir "C:\Apps\MyApp" `
             -AppToLaunch "C:\Apps\MyApp\app.exe" `
             -AppName "Mon Application CRM" `
             -AppDescription "Version depuis build server"
```

### Lancement optimisé :
```powershell
# Lancement direct (gestion auto des processus)
.\launch.ps1

# Depuis share réseau (avec copie temporaire)
.\launch.ps1 -FromShare

# Kill forcé des processus existants
.\launch.ps1 -KillExisting

# Combiné pour automation
.\launch.ps1 \\server\tools\SyncOtter.exe -FromShare -KillExisting
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
1. **Build une fois** : `.\build.ps1 -Type ultra`
2. **Déployer** : `.\deploy.ps1 -DestinationPath "\\server\tools\SyncOtter"`
3. **Lancer depuis poste** : `.\launch.ps1 \\server\tools\SyncOtter\SyncOtter-*.exe -FromShare`

### **Approche Multi-Configurations :**
1. **Build une fois** : `.\build.ps1 -Type ultra`
2. **Déployer pour App A** : 
   ```powershell
   .\deploy.ps1 -DestinationPath "\\server\tools\AppA" `
                -SourceDir "\\build\AppA" `
                -TargetDir "C:\Apps\AppA" `
                -AppName "Application A"
   ```
3. **Déployer pour App B** :
   ```powershell
   .\deploy.ps1 -DestinationPath "\\server\tools\AppB" `
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
.\build.ps1 -Type ultra      # Ultra-léger portable
.\build.ps1 -Type portable   # Portable standard  
.\build.ps1 -Type installer  # Installateur léger
.\build.ps1 -Type dev        # Mode développement

# DÉPLOIEMENT
.\deploy.ps1 -DestinationPath "C:\Tools"  # Déploiement simple
.\deploy.ps1 [params...]                  # Déploiement personnalisé

# LANCEMENT  
.\launch.ps1                 # Auto-détection exe
.\launch.ps1 path\to\app.exe # Exe spécifique
.\launch.ps1 -FromShare      # Optimisé share réseau
```

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