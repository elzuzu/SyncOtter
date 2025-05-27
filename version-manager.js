const fs = require('fs');
const path = require('path');
const https = require('https');

function getCurrentVersion() {
  const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8'));
  return pkg.version;
}

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https.get(url, response => {
      response.pipe(file);
      file.on('finish', () => file.close(resolve));
    }).on('error', err => {
      fs.unlink(dest, () => reject(err));
    });
  });
}

async function checkForUpdates() {
  const updateUrl = process.env.SYNCOTTER_UPDATE_MANIFEST;
  if (!updateUrl) return;

  return new Promise((resolve, reject) => {
    https.get(updateUrl, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', async () => {
        try {
          const manifest = JSON.parse(data);
          const current = getCurrentVersion();
          if (manifest.version && manifest.version !== current) {
            console.log(`New version available: ${manifest.version}`);
            const tmp = path.join(process.cwd(), 'update.tmp');
            await downloadFile(manifest.url, tmp);
            // TODO: replace executable atomically
            console.log('Update downloaded');
          }
          resolve();
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

module.exports = { checkForUpdates };
