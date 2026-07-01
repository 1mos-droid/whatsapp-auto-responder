require('dotenv').config();
const { default: makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion } = require('@whiskeysockets/baileys');
const qrcode = require('qrcode-terminal');
const pino = require('pino');
const Groq = require('groq-sdk');
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

// Initialize Groq Client
const groq = new Groq({ apiKey: process.env.GROQ_API_KEY });
const CONFIG_PATH = path.join(__dirname, 'config.json');

// ponytail: simplified configuration handling
function getConfig() {
    try {
        return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    } catch {
        return { isActive: false, systemPrompt: "You are a helpful assistant.", allowedChats: [] };
    }
}

function saveConfig(config) {
    try {
        fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
    } catch (error) {
        console.error("Config save failed:", error.message);
    }
}

// --- EXPRESS SERVER ---
const app = express();
app.use(express.json());
app.use(cors());

app.get('/status', (req, res) => res.json(getConfig()));

app.post('/toggle', (req, res) => {
    const config = getConfig();
    config.isActive = !config.isActive;
    saveConfig(config);
    res.json({ success: true, isActive: config.isActive });
});

app.post('/prompt', (req, res) => {
    const config = getConfig();
    config.systemPrompt = req.body.newPrompt || config.systemPrompt;
    saveConfig(config);
    res.json({ success: true, systemPrompt: config.systemPrompt });
});

app.post('/chats/add', (req, res) => {
    const config = getConfig();
    if (!config.allowedChats.includes(req.body.jid)) {
        config.allowedChats.push(req.body.jid);
        saveConfig(config);
    }
    res.json({ success: true, allowedChats: config.allowedChats });
});

app.post('/chats/remove', (req, res) => {
    const config = getConfig();
    config.allowedChats = config.allowedChats.filter(id => id !== req.body.jid);
    saveConfig(config);
    res.json({ success: true, allowedChats: config.allowedChats });
});

app.listen(3000, '0.0.0.0', () => console.log('[API] Running on port 3000'));

// ponytail: direct AI response generation
async function generateAIResponse(userMessage, systemPrompt) {
    try {
        const completion = await groq.chat.completions.create({
            messages: [
                { role: "system", content: systemPrompt },
                { role: "user", content: userMessage }
            ],
            model: "llama-3.1-8b-instant",
        });
        return completion.choices[0]?.message?.content || "No response.";
    } catch (error) {
        console.error("AI Error:", error.message);
        return "Service unavailable.";
    }
}

// ponytail: replaced over-engineered reading/typing delay calculation with a simple random delay
const getStealthDelay = () => Math.floor(Math.random() * 2000) + 1500;

// Main WhatsApp connection logic
async function connectToWhatsApp() {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info');
    const { version } = await fetchLatestBaileysVersion();

    const sock = makeWASocket({
        version,
        auth: state,
        printQRInTerminal: false,
        logger: pino({ level: 'silent' }),
    });

    sock.ev.on('connection.update', (update) => {
        const { connection, lastDisconnect, qr } = update;
        if (qr) qrcode.generate(qr, { small: true });
        if (connection === 'close') {
            const shouldReconnect = lastDisconnect.error?.output?.statusCode !== DisconnectReason.loggedOut;
            if (shouldReconnect) connectToWhatsApp();
        } else if (connection === 'open') {
            console.log('WhatsApp connection open.');
        }
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('messages.upsert', async (m) => {
        const msg = m.messages[0];
        if (!msg.message || msg.key.fromMe || msg.key.remoteJid === 'status@broadcast') return;

        const incomingText = msg.message.conversation || msg.message.extendedTextMessage?.text;
        if (!incomingText) return;

        const senderJid = msg.key.remoteJid;
        const config = getConfig();

        // ponytail: simplified bot active and whitelist checks
        if (!config.isActive) return;
        if (!config.allowedChats || config.allowedChats.length === 0 || !config.allowedChats.includes(senderJid)) {
            console.log(`[Filter] Ignored sender ${senderJid}`);
            return;
        }

        const aiResponse = await generateAIResponse(incomingText, config.systemPrompt);
        const delay = getStealthDelay();

        await sock.sendPresenceUpdate('composing', senderJid);
        await new Promise(resolve => setTimeout(resolve, delay));
        await sock.sendMessage(senderJid, { text: aiResponse }, { quoted: msg });
        await sock.sendPresenceUpdate('paused', senderJid);
    });
}

connectToWhatsApp().catch(err => console.error("Error:", err));
