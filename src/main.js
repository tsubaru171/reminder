const { app, BrowserWindow, Tray, Menu, ipcMain, screen, nativeImage, shell, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const { autoUpdater } = require('electron-updater');

// ── Paths ─────────────────────────────────────────────────────────────────────
const USER_DATA = app.getPath('userData');
const CONFIG_PATH = path.join(USER_DATA, 'config.json');

// ── Config helpers ────────────────────────────────────────────────────────────
function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    }
  } catch (e) { console.error('Config read error:', e.message); }
  return { supabaseUrl: '', supabaseAnonKey: '' };
}

function saveConfig(data) {
  try {
    fs.mkdirSync(USER_DATA, { recursive: true });
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(data, null, 2));
  } catch (e) { console.error('Config write error:', e.message); }
}

// ── State ─────────────────────────────────────────────────────────────────────
let mainWindow = null;
let alertWindow = null;
let tray = null;
let isQuitting = false;

// ── Main Window ───────────────────────────────────────────────────────────────
function createMainWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 800,
    minWidth: 800,           // Giới hạn nhỏ nhất để UI không vỡ
    minHeight: 600,
    title: 'RemindBoard',
    icon: path.join(__dirname, '..', 'assets', 'icon.ico'),
    backgroundColor: '#F5F0E8',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
      webSecurity: true,
    },
    show: false,
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));

  mainWindow.webContents.on('did-fail-load', (_, code, desc) => {
    console.error('Page load failed:', code, desc);
  });

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    mainWindow.focus();
  });

  // Hide to tray on close — keep running in background
  mainWindow.on('close', (e) => {
    if (!isQuitting) {
      e.preventDefault();
      mainWindow.hide();
    }
  });

  return mainWindow;
}

// ── Alert Window (fullscreen popup) ──────────────────────────────────────────
function bringAlertToFront(win) {
  if (!win || win.isDestroyed()) return;
  // Step 1: guarantee the window is visible (this always works)
  win.show();
  win.focus();
  // Step 2: elevate z-order — wrap risky calls so a failure can't abort show()
  try { win.setAlwaysOnTop(true, 'screen-saver', 1); } catch(e) {}
  try { win.moveTop(); } catch(e) {}
  try { app.focus({ steal: true }); } catch(e) {} // macOS + some Linux; no-op on Windows
}

function showAlertWindow(reminderData) {
  // If alert already open, refresh data and re-assert focus
  if (alertWindow && !alertWindow.isDestroyed()) {
    alertWindow.webContents.send('new-alert', reminderData);
    bringAlertToFront(alertWindow);
    return;
  }

  const display = screen.getPrimaryDisplay();
  const { x, y, width, height } = display.bounds;

  alertWindow = new BrowserWindow({
    x,
    y,
    width,
    height,
    frame: false,
    alwaysOnTop: true,
    resizable: false,
    skipTaskbar: false,
    show: false,                // hidden until ready — prevents blank flash
    backgroundColor: '#000000',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  try { alertWindow.setAlwaysOnTop(true, 'screen-saver', 1); } catch(e) {}

  alertWindow.loadFile(path.join(__dirname, 'alert.html'));

  currentAlertReminderId = reminderData?.id || null;

  alertWindow.once('ready-to-show', () => {
    // Send data first so UI is ready before window appears
    alertWindow.webContents.send('new-alert', reminderData);
    bringAlertToFront(alertWindow);
  });

  alertWindow.on('closed', () => { alertWindow = null; currentAlertReminderId = null; });
}

// ── System Tray ───────────────────────────────────────────────────────────────
function createTray() {
  // Create a simple 16x16 icon programmatically
  const iconPath = path.join(__dirname, '..', 'assets', 'tray-icon.png');
  let trayIcon;

  if (fs.existsSync(iconPath)) {
    trayIcon = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });
  } else {
    // Fallback: empty icon (app still works)
    trayIcon = nativeImage.createEmpty();
  }

  tray = new Tray(trayIcon);
  tray.setToolTip('RemindBoard — Team Reminders');
  tray.on('click', () => { mainWindow?.show(); mainWindow?.focus(); });
  tray.on('double-click', () => { mainWindow?.show(); mainWindow?.focus(); });
  updateTrayMenu();
}

// ── IPC Handlers ─────────────────────────────────────────────────────────────
ipcMain.handle('get-config', () => loadConfig());

ipcMain.handle('save-config', (_, data) => {
  saveConfig(data);
  return true;
});

ipcMain.handle('show-alert', (_, reminderData) => {
  showAlertWindow(reminderData);
  return true;
});

ipcMain.on('dismiss-alert', (_, data) => {
  if (alertWindow && !alertWindow.isDestroyed()) {
    alertWindow.close();
  }
  // Always bring main window to front when user acknowledges an alert
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.show();
    mainWindow.focus();
    // Forward reminder data so renderer can schedule re-alerts
    if (data) mainWindow.webContents.send('alert-dismissed', data);
  }
});

// Track snooze timers by reminder ID so they can be cancelled on delete
const snoozedAlerts = new Map(); // reminderId → timeoutId
// Track which reminder is currently shown in the alert window
let currentAlertReminderId = null;

ipcMain.on('snooze-alert', (_, { minutes, data }) => {
  if (alertWindow && !alertWindow.isDestroyed()) {
    alertWindow.close();
    currentAlertReminderId = null;
  }
  const tid = setTimeout(() => {
    snoozedAlerts.delete(data?.id);
    showAlertWindow(data);
  }, minutes * 60 * 1000);
  if (data?.id) snoozedAlerts.set(data.id, tid);
});

ipcMain.on('cancel-reminder-alerts', (_, id) => {
  // Cancel snooze timer
  const tid = snoozedAlerts.get(id);
  if (tid) { clearTimeout(tid); snoozedAlerts.delete(id); }
  // Close alert window if it's showing this reminder
  if (currentAlertReminderId === id && alertWindow && !alertWindow.isDestroyed()) {
    alertWindow.close();
    currentAlertReminderId = null;
  }
});

ipcMain.on('open-main', () => {
  mainWindow?.show();
  mainWindow?.focus();
});

ipcMain.handle('open-external', (_, url) => {
  shell.openExternal(url);
});

// ── Autostart helpers ─────────────────────────────────────────────────────────
function getAutostartEnabled() {
  return app.getLoginItemSettings().openAtLogin;
}

function setAutostart(enable) {
  app.setLoginItemSettings({
    openAtLogin: enable,
    openAsHidden: true, // macOS: start hidden in dock
    args: enable ? ['--hidden'] : [],
  });
}

ipcMain.handle('get-autostart', () => getAutostartEnabled());

ipcMain.handle('set-autostart', (_, enable) => {
  setAutostart(enable);
  // Update tray menu to reflect new state
  updateTrayMenu();
  return true;
});

function updateTrayMenu() {
  if (!tray) return;
  const autostartEnabled = getAutostartEnabled();
  const menu = Menu.buildFromTemplate([
    { label: '📋 Open RemindBoard', click: () => { mainWindow?.show(); mainWindow?.focus(); } },
    { type: 'separator' },
    {
      label: autostartEnabled ? '✓ Khởi động cùng Windows' : '  Khởi động cùng Windows',
      click: () => setAutostart(!autostartEnabled) && updateTrayMenu(),
    },
    { type: 'separator' },
    { label: 'Quit', click: () => { isQuitting = true; app.quit(); } },
  ]);
  tray.setContextMenu(menu);
}

// ── Auto Updater ──────────────────────────────────────────────────────────────
function setupAutoUpdater() {
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;

  autoUpdater.on('update-available', (info) => {
    mainWindow?.webContents.send('update-available', info.version);
  });

  autoUpdater.on('update-downloaded', () => {
    dialog.showMessageBox(mainWindow, {
      type: 'info',
      title: 'Cập nhật sẵn sàng',
      message: 'Đã tải bản cập nhật mới. Khởi động lại để áp dụng?',
      buttons: ['Khởi động lại', 'Để sau'],
      defaultId: 0,
    }).then(({ response }) => {
      if (response === 0) autoUpdater.quitAndInstall();
    });
  });

  autoUpdater.on('error', (err) => {
    console.error('Auto-updater error:', err.message);
  });

  // Check for updates 5 seconds after launch, then every 4 hours
  setTimeout(() => autoUpdater.checkForUpdates(), 5000);
  setInterval(() => autoUpdater.checkForUpdates(), 4 * 60 * 60 * 1000);
}

ipcMain.handle('check-for-updates', () => autoUpdater.checkForUpdates());

// ── App Lifecycle ─────────────────────────────────────────────────────────────
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {

app.on('second-instance', () => {
  if (mainWindow) {
    if (mainWindow.isMinimized() || !mainWindow.isVisible()) mainWindow.show();
    mainWindow.focus();
  }
});

app.whenReady().then(() => {
  // Detect if launched at login (Windows passes --hidden arg)
  const launchedHidden = process.argv.includes('--hidden')
    || app.getLoginItemSettings().wasOpenedAtLogin;

  // Enable autostart by default on first install (only when packaged)
  if (app.isPackaged) {
    const cfg = loadConfig();
    if (!cfg.autostartDefaultSet) {
      setAutostart(true);
      saveConfig({ ...cfg, autostartDefaultSet: true });
    }
  }

  createMainWindow();
  createTray();
  if (app.isPackaged) setupAutoUpdater();

  // Hide window if started automatically at login
  if (launchedHidden) {
    mainWindow?.hide();
  }

  app.on('activate', () => {
    // macOS: re-open window when clicking dock icon
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    } else {
      mainWindow?.show();
    }
  });
});

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray (except macOS which has dock)
  if (process.platform !== 'darwin') {
    // Still keep running via tray
  }
});

app.on('before-quit', () => {
  isQuitting = true;
});

} // end single-instance lock
