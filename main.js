// Козырная Арена — оболочка Electron для Windows, macOS и Linux.
'use strict';
const { app, BrowserWindow, Menu, shell } = require('electron');
const path = require('path');
const { startServer } = require('./server');

const WEB = path.join(__dirname, 'web');

if (!app.requestSingleInstanceLock()) app.quit();

async function createWindow() {
  // На macOS оставляем стандартное меню (Cmd+Q, копирование), на остальных — без меню
  Menu.setApplicationMenu(process.platform === 'darwin'
    ? Menu.buildFromTemplate([{ role: 'appMenu' }, { role: 'editMenu' }, { role: 'windowMenu' }])
    : null);

  let port = null;
  try { port = await startServer(WEB); } catch (_) { /* без LAN: откроем файл напрямую, онлайн и одиночная игра работают */ }

  const win = new BrowserWindow({
    width: 1500, height: 920, minWidth: 1000, minHeight: 680,
    backgroundColor: '#120d19', title: 'Козырная Арена', show: false,
    icon: path.join(__dirname, 'build', 'icon.png'),
    webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false, backgroundThrottling: false },
  });
  win.once('ready-to-show', () => { win.maximize(); win.show(); });
  win.on('page-title-updated', e => e.preventDefault());
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:\/\//.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (e, url) => {
    if (!url.startsWith('http://127.0.0.1:') && !url.startsWith('file://')) { e.preventDefault(); shell.openExternal(url); }
  });
  if (port) win.loadURL('http://127.0.0.1:' + port + '/');
  else win.loadFile(path.join(WEB, 'index.html'));
}

app.on('second-instance', () => {
  const w = BrowserWindow.getAllWindows()[0];
  if (w) { if (w.isMinimized()) w.restore(); w.focus(); }
});
app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());
