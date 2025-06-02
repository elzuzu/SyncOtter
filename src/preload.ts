import { contextBridge, ipcRenderer } from 'electron';

const ALLOWED_CHANNELS = ['update-status', 'update-progress', 'request-shutdown', 'health-report', 'telemetry-summary'];
contextBridge.exposeInMainWorld('electronAPI', {
  send: (channel: string, data: any) => {
    if (ALLOWED_CHANNELS.includes(channel)) {
      ipcRenderer.send(channel, data);
    }
  },
  invoke: (channel: string, data: any) => {
    if (ALLOWED_CHANNELS.includes(channel)) {
      return ipcRenderer.invoke(channel, data);
    }
  },
  on: (channel: string, func: (...args: any[]) => void) => {
    if (ALLOWED_CHANNELS.includes(channel)) {
      ipcRenderer.on(channel, (event, ...args) => func(...args));
    }
  }
});
