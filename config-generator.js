const fs = require('fs');
const path = require('path');
const Ajv = require('ajv');
const yargs = require('yargs');

const argv = yargs.option('env', { alias: 'e', default: 'dev' }).argv;
const templatePath = path.join(__dirname, 'config.exemple.json');
const schema = {
  type: 'object',
  properties: {
    sourceDirectory: { type: 'string' },
    targetDirectory: { type: 'string' },
    executeAfterSync: { type: 'string' },
    appName: { type: 'string' },
    appDescription: { type: 'string' }
  },
  required: ['sourceDirectory', 'targetDirectory']
};

const template = JSON.parse(fs.readFileSync(templatePath, 'utf8'));

const envOverrides = {
  dev: {
    appDescription: 'Configuration développement'
  },
  staging: {
    appDescription: 'Configuration staging'
  },
  prod: {
    appDescription: 'Configuration production'
  }
}[argv.env] || {};

const finalConfig = { ...template, ...envOverrides };

for (const [key, value] of Object.entries(process.env)) {
  if (finalConfig.hasOwnProperty(key)) {
    finalConfig[key] = value;
  }
}

const ajv = new Ajv();
const validate = ajv.compile(schema);
if (!validate(finalConfig)) {
  console.error('Configuration invalide:', validate.errors);
  process.exit(1);
}

const outputFile = path.join(__dirname, `config.${argv.env}.json`);
fs.writeFileSync(outputFile, JSON.stringify(finalConfig, null, 2));
console.log(`Config generated: ${outputFile}`);
