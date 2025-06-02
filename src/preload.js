"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const electron_1 = require("electron");
const ALLOWED_CHANNELS = [
    'update-status',
    'update-progress',
    'request-shutdown',
    'health-report',
    'telemetry-summary'
];
electron_1.contextBridge.exposeInMainWorld('electronAPI', {
    send: (channel, data) => {
        if (ALLOWED_CHANNELS.includes(channel)) {
            electron_1.ipcRenderer.send(channel, data);
        }
    },
    invoke: (channel, data) => {
        if (ALLOWED_CHANNELS.includes(channel)) {
            return electron_1.ipcRenderer.invoke(channel, data);
        }
    },
    on: (channel, func) => {
        if (ALLOWED_CHANNELS.includes(channel)) {
            electron_1.ipcRenderer.on(channel, (event, ...args) => func(...args));
        }
    }
});
