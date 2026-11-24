// На macOS подписываем приложение ad-hoc подписью: без неё сборка для Apple Silicon не запустится.
// (Это не подпись Apple: при первом запуске macOS всё равно попросит подтверждение — см. README.)
const { execFileSync } = require('child_process');
const path = require('path');

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'darwin') return;
  const app = path.join(context.appOutDir, context.packager.appInfo.productFilename + '.app');
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', app], { stdio: 'inherit' });
};
