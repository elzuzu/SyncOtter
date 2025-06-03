# 🦦 SyncOtter - Synchronisation Ultra-Légère

SyncOtter est un outil de synchronisation simplifié pouvant être compilé avec **Deno**.

## 🚀 Utilisation rapide

1. Placez votre configuration dans `config.json` à côté de l'exécutable.
2. Compilez l'outil :
   ```powershell
   ./build-deno.ps1
   ```
   Le binaire est généré dans `deno-dist/SyncOtter-Single.exe`.
3. Lancez l'exécutable pour démarrer la synchronisation.

## Exemple de `config.json`

```json
{
  "sourceDirectory": "C:\\Source",
  "targetDirectory": "C:\\Target",
  "excludeDirectories": [".git", "node_modules"],
  "excludePatterns": ["*.tmp", "*.log"],
  "executeAfterSync": "C:\\Target\\app.exe"
}
```

## Fonctionnement

Le script Deno parcourt le répertoire source et copie uniquement les fichiers nouveaux ou modifiés vers le répertoire cible. À la fin de la synchronisation, la commande définie dans `executeAfterSync` est exécutée si elle est renseignée.
