const { app, BrowserWindow, ipcMain, nativeTheme } = require('electron');
const path = require('node:path');

// Handle creating/removing shortcuts on Windows when installing/uninstalling.
if (require('electron-squirrel-startup')) {
  app.quit();
}

// The harness's settings, from the test app spec. The page reads them through the preload.
const settings = {
  page: process.env.TESTAPP_PAGE ?? '',
  mark: process.env.TESTAPP_MARK === '1',
  scroll: process.env.TESTAPP_SCROLL === '1',
  scrollSeconds: Number(process.env.TESTAPP_SCROLL_SECONDS ?? 20) || 20,
};

ipcMain.on('testapp:settings', (event) => {
  event.returnValue = settings;
});
ipcMain.on('testapp:print', (_event, text) => {
  process.stdout.write(`${text}\n`);
});
ipcMain.on('testapp:quit', () => app.quit());

// The shared React app: its dev server while it runs, or its build. The release carries the build
// in Resources, as forge.config.js asks.
const loadPage = (window) => {
  if (process.env.RUKUN_DEV_URL) return window.loadURL(process.env.RUKUN_DEV_URL);

  const folder = app.isPackaged ? process.resourcesPath : path.join(__dirname, '../../web');
  return window.loadFile(path.join(folder, 'dist', 'index.html'));
};

const createWindow = () => {
  const mainWindow = new BrowserWindow({
    title: 'Rukun',
    width: 1100,
    height: 720,
    minWidth: 900,
    minHeight: 600,
    useContentSize: true,
    titleBarStyle: 'hidden',
    backgroundColor: '#121214',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  loadPage(mainWindow);
};

app.whenReady().then(() => {
  nativeTheme.themeSource = 'dark';
  createWindow();

  // On OS X it's common to re-create a window in the app when the
  // dock icon is clicked and there are no other windows open.
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

// Quit when all windows are closed, except on macOS. There, it's common
// for applications and their menu bar to stay active until the user quits
// explicitly with Cmd + Q.
app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
