#!/usr/bin/env node

/**
 * Jam Session Test Client for Nuage
 * Usage:
 *   node scripts/jam_tester.js [ROOM_CODE] [NAME]
 * Example:
 *   node scripts/jam_tester.js JAM-1234 Alex
 */

const readline = require('readline');

const args = process.argv.slice(2);
const roomCode = (args[0] || 'JAM-TEST').toUpperCase();
const userName = args[1] || 'Тестовый слушатель';

const SUPABASE_WS_URL = 'wss://iszyybmeswfvlfjhetii.supabase.co/realtime/v1/websocket?apikey=sb_publishable_ZtoIZz-On-YcFSD3ReFC_g_eJ9sBpKY&vsn=1.0.0';
const topic = `realtime:jam-${roomCode}`;

console.log('\x1b[36m%s\x1b[0m', `=== Nuage Jam Session Tester ===`);
console.log(`Подключение к комнате: \x1b[33m${roomCode}\x1b[0m`);
console.log(`Имя участника: \x1b[32m${userName}\x1b[0m`);
console.log('-------------------------------------------');

const ws = new WebSocket(SUPABASE_WS_URL);
let refCount = 1;
let heartbeatInterval = null;
let presenceInterval = null;
let hasJoined = false;
const clientUserId = 'tester_' + Math.random().toString(36).substring(2, 8);

function send(event, payload, customTopic = topic) {
    if (ws.readyState !== WebSocket.OPEN) return;
    const msg = {
        topic: customTopic,
        event: event,
        payload: payload,
        ref: String(refCount++)
    };
    ws.send(JSON.stringify(msg));
}

function broadcast(subEvent, data) {
    send('broadcast', {
        type: 'broadcast',
        event: subEvent,
        payload: data
    });
}

function announcePresence() {
    broadcast('presence', {
        id: clientUserId,
        name: userName,
        avatarURL: 'https://a-v2.sndcdn.com/assets/images/default/avatar--large-9be1a704.png',
        isHost: false
    });
}

function sendReaction(emoji) {
    broadcast('reaction', {
        id: 'rx_' + Date.now(),
        emoji: emoji,
        fromUser: userName
    });
    console.log(`\x1b[35m[Отправлена реакция]\x1b[0m ${emoji}`);
}

ws.onopen = () => {
    console.log('\x1b[32m✔ WebSocket соединение установлено!\x1b[0m');

    // 1. Join channel
    send('phx_join', {
        config: { broadcast: { ack: true } }
    });

    // 2. Heartbeat every 20s
    heartbeatInterval = setInterval(() => {
        send('heartbeat', {}, 'phoenix');
    }, 20000);

    // 3. Announce presence periodically
    announcePresence();
    presenceInterval = setInterval(() => {
        announcePresence();
    }, 12000);

    setupKeyboardControls();
};

ws.onmessage = (event) => {
    try {
        const msg = JSON.parse(event.data);

        if (msg.event === 'phx_reply' && msg.payload?.status === 'ok') {
            if (!hasJoined) {
                hasJoined = true;
                console.log(`\x1b[32m✔ Успешно вошли в канал: ${topic}\x1b[0m`);
                console.log('\x1b[90mУправление клавишами:\x1b[0m');
                console.log('  [1] 🔥   [2] ❤️   [3] 💀   [4] ⚡️   [5] 🎉   [q] Выйти\n');
            }
        }

        if (msg.event === 'broadcast') {
            const inner = msg.payload;
            const subEvent = inner?.event;
            const data = inner?.payload;

            if (subEvent === 'playback_sync') {
                const mins = Math.floor((data.progress || 0) / 60);
                const secs = Math.floor((data.progress || 0) % 60).toString().padStart(2, '0');
                const state = data.isPlaying ? '▶️ Играет' : '⏸ Пауза';
                console.log(`\x1b[33m[СИНХРОНИЗАЦИЯ]\x1b[0m ${state} | "${data.trackTitle}" - ${data.artistName} (${mins}:${secs}) | Ведущий: ${data.hostName || 'Хост'}`);
            } else if (subEvent === 'reaction') {
                console.log(`\x1b[35m[РЕАКЦИЯ В КОМНАТЕ]\x1b[0m ${data.fromUser}: ${data.emoji}`);
            } else if (subEvent === 'presence') {
                if (data.name !== userName) {
                    console.log(`\x1b[34m[УЧАСТНИК В СЕТИ]\x1b[0m ${data.name} ${data.isHost ? '👑 (Ведущий)' : '🎧 (Слушатель)'}`);
                }
            } else if (subEvent === 'host_ended') {
                console.log('\x1b[31m[ВЕДУЩИЙ ЗАВЕРШИЛ КОМНАТУ]\x1b[0m');
            }
        }
    } catch (e) {
        // ignore parse errors
    }
};

ws.onerror = (err) => {
    console.error('\x1b[31mОшибка WebSocket:\x1b[0m', err.message || err);
};

ws.onclose = () => {
    console.log('\x1b[31mСоединение закрыто.\x1b[0m');
    clearInterval(heartbeatInterval);
    clearInterval(presenceInterval);
    process.exit(0);
};

function setupKeyboardControls() {
    readline.emitKeypressEvents(process.stdin);
    if (process.stdin.isTTY) {
        process.stdin.setRawMode(true);
    }

    process.stdin.on('keypress', (str, key) => {
        if (key.ctrl && key.name === 'c' || str === 'q') {
            console.log('\nВыход...');
            ws.close();
            process.exit(0);
        }

        switch (str) {
            case '1': sendReaction('🔥'); break;
            case '2': sendReaction('❤️'); break;
            case '3': sendReaction('💀'); break;
            case '4': sendReaction('⚡️'); break;
            case '5': sendReaction('🎉'); break;
        }
    });
}
