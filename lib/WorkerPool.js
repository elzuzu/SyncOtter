const { Worker } = require('worker_threads');

class WorkerPool {
  constructor(script, size) {
    this.script = script;
    this.size = size;
    this.workers = [];
    this.queue = [];
    this.idle = [];
    for (let i = 0; i < size; i++) this._addWorker();
  }

  _addWorker() {
    const worker = new Worker(this.script);
    worker.on('message', (msg) => {
      const { resolve } = worker.currentTask;
      worker.currentTask = null;
      this.idle.push(worker);
      resolve(msg);
      this._next();
    });
    worker.on('error', (err) => {
      const { reject } = worker.currentTask || {};
      worker.terminate();
      this._addWorker();
      if (reject) reject(err);
    });
    this.workers.push(worker);
    this.idle.push(worker);
  }

  run(data) {
    return new Promise((resolve, reject) => {
      this.queue.push({ data, resolve, reject });
      this.queue.sort((a,b)=>a.data.size-b.data.size); // priority by size
      this._next();
    });
  }

  _next() {
    if (!this.queue.length || !this.idle.length) return;
    const worker = this.idle.shift();
    const task = this.queue.shift();
    worker.currentTask = task;
    worker.postMessage(task.data);
  }

  destroy() {
    this.workers.forEach(w => w.terminate());
  }
}

module.exports = WorkerPool;
