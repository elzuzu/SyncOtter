const chalk = require('chalk');
const cliProgress = require('cli-progress');

class CliInterface {
  constructor() {
    this.bar = null;
  }

  showAppInfo(info = {}) {
    console.log(chalk.cyan(`SyncOtter ${info.version || ''}`));
    if (info.executeAfterSync) {
      console.log(chalk.cyan(`Post-sync: ${info.executeAfterSync}`));
    }
  }

  showStatus(message) {
    const color = message.includes('❌') ? chalk.red
      : message.includes('✅') ? chalk.green
      : message.includes('⚠️') ? chalk.yellow
      : chalk.white;
    console.log(color(message));
  }

  startProgress(total) {
    this.bar = new cliProgress.SingleBar({
      format: `${chalk.blue('{bar}')} {percentage}% | {value}/{total} | {file} | {copied} copied`,
      barCompleteChar: '\u2588',
      barIncompleteChar: '\u2591',
      hideCursor: true
    }, cliProgress.Presets.shades_classic);
    this.bar.start(total, 0, { file: '', copied: 0 });
  }

  updateProgress(data) {
    if (!this.bar) this.startProgress(data.total);
    this.bar.update(data.current, { file: data.fileName, copied: data.copied });
    if (data.current >= data.total) {
      this.bar.stop();
    }
  }
}

module.exports = CliInterface;
