const { parentPort } = require('worker_threads');
const fs = require('fs-extra');

parentPort.on('message', async (task) => {
  const { source, target, attempt = 1 } = task;
  try {
    await fs.ensureDir(require('path').dirname(target));
    await fs.copy(source, target);
    parentPort.postMessage({ success: true, source, target });
  } catch (err) {
    if (attempt < 3) {
      const delay = Math.pow(2, attempt) * 100;
      setTimeout(() => {
        parentPort.postMessage({ retry: true, source, target, attempt: attempt + 1 });
      }, delay);
    } else {
      parentPort.postMessage({ success: false, source, target, error: err.message });
    }
  }
});
