// Renders build/icon.html's canvas to build/icon_raw.png. Run: electron build/gen-icon.js
const { app, BrowserWindow } = require('electron');
const fs = require('fs');
const path = require('path');

app.disableHardwareAcceleration();

app.whenReady().then(() => {
  const win = new BrowserWindow({ show: false, width: 1100, height: 1100 });

  win.webContents.on('console-message', (_e, _level, message) => {
    if (message.startsWith('data:image/png;base64,')) {
      fs.writeFileSync(
        path.join(__dirname, 'icon_raw.png'),
        Buffer.from(message.split(',')[1], 'base64')
      );
      console.log('icon written');
      app.quit();
    }
  });

  win.loadFile(path.join(__dirname, 'icon.html'));
  setTimeout(() => { console.error('timed out'); app.exit(1); }, 15000);
});
