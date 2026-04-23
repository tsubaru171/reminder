const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  // Config
  getConfig:    ()    => ipcRenderer.invoke('get-config'),
  saveConfig:   (cfg) => ipcRenderer.invoke('save-config', cfg),

  // Alert window
  showAlert:    (r)   => ipcRenderer.invoke('show-alert', r),
  dismissAlert:         (data)          => ipcRenderer.send('dismiss-alert', data),
  snoozeAlert:          (minutes, data) => ipcRenderer.send('snooze-alert', { minutes, data }),
  cancelReminderAlerts: (id)            => ipcRenderer.send('cancel-reminder-alerts', id),
  openMain:     ()    => ipcRenderer.send('open-main'),

  // System
  openExternal:   (url)  => ipcRenderer.invoke('open-external', url),
  getAutostart:   ()     => ipcRenderer.invoke('get-autostart'),
  setAutostart:   (bool) => ipcRenderer.invoke('set-autostart', bool),

  // Events FROM main → renderer
  onNewAlert:       (cb) => ipcRenderer.on('new-alert',       (_, data) => cb(data)),
  onAlertDismissed: (cb) => ipcRenderer.on('alert-dismissed', (_, data) => cb(data)),
});
