const fs = require('fs');
const path = require('path');

class ReportGenerator {
  constructor(outputDir = 'reports') {
    this.outputDir = outputDir;
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
  }

  generate(metrics) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const file = path.join(this.outputDir, `report-${timestamp}.json`);
    fs.writeFileSync(file, JSON.stringify(metrics, null, 2));
    return file;
  }
}

module.exports = ReportGenerator;
