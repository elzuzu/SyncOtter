const Config = require('../lib/Config');
const SyncEngine = require('../lib/SyncEngine');
const { performance } = require('perf_hooks');

(async () => {
  const config = new Config();
  const engine = new SyncEngine(config, 'turbo');
  const start = performance.now();
  await engine.sync();
  const duration = ((performance.now() - start)/1000).toFixed(2);
  console.log(`Sync completed in ${duration}s for ${engine.progress.total} files`);
})();
