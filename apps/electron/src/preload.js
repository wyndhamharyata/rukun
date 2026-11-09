// See the Electron documentation for details on how to use preload scripts:
// https://www.electronjs.org/docs/latest/tutorial/process-model#preload-scripts
const { contextBridge, ipcRenderer } = require('electron');

// The shared React app reads the harness's settings and prints through window.testapp.
contextBridge.exposeInMainWorld('testapp', {
  settings: ipcRenderer.sendSync('testapp:settings'),
  print: (text) => ipcRenderer.send('testapp:print', text),
  quit: () => ipcRenderer.send('testapp:quit'),
});
