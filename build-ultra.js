const path = require('path');
const fs = require('fs');
const { promisify } = require('util');
const webpack = require('webpack');
const CompressionPlugin = require('compression-webpack-plugin');

if (!require('fs').existsSync('./main.js')) {
  console.error('main.js not found');
  process.exit(1);
}

async function runWebpack() {
  const compiler = webpack({
    mode: 'production',
    target: 'electron-main',
    entry: './main.js',
    output: {
      filename: 'bundle.js',
      path: path.resolve(__dirname, 'out')
    },
    optimization: {
      usedExports: true,
      minimize: true
    },
    plugins: [
      new CompressionPlugin({
        filename: 'bundle.js.br',
        algorithm: 'brotliCompress',
        test: /bundle\.js$/,
        compressionOptions: { level: 11 },
        deleteOriginalAssets: false
      })
    ]
  });

  const run = promisify(compiler.run.bind(compiler));
  await run();
}

(async () => {
  try {
    console.log('Starting webpack build...');
    await runWebpack();
    const bundlePath = path.join(__dirname, 'out', 'bundle.js.br');
    if (fs.existsSync(bundlePath)) {
      const stats = fs.statSync(bundlePath);
      console.log(`Built bundle: ${bundlePath} (${(stats.size / 1024).toFixed(2)} KB)`);
    } else {
      console.log('Bundle created successfully');
    }
  } catch (err) {
    console.error('Build failed:', err.message);
    process.exit(1);
  }
})();
