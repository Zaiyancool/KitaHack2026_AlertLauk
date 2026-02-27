const express = require('express');
const cors = require('cors');
const NodeCache = require('node-cache');
const axios = require('axios');

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

// Simple in-memory cache and rate-limiter (suitable for small-team hackathon prototype)
const cache = new NodeCache({ stdTTL: 60 }); // 60s cache
const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const MAX_PER_WINDOW = process.env.MAX_PER_MINUTE ? parseInt(process.env.MAX_PER_MINUTE) : 30;
const clients = new Map();

function rateLimit(key) {
  const now = Date.now();
  if (!clients.has(key)) clients.set(key, []);
  const arr = clients.get(key);
  while (arr.length && arr[0] <= now - RATE_LIMIT_WINDOW_MS) arr.shift();
  if (arr.length >= MAX_PER_WINDOW) return false;
  arr.push(now);
  return true;
}

const STUDIO_API_URL = process.env.STUDIO_API_URL; // set to your Studio/Generative endpoint
const STUDIO_API_KEY = process.env.STUDIO_API_KEY; // API key (or use Secret Manager in production)

// POST /chat { message, userId }
app.post('/chat', async (req, res) => {
  try {
    const { message, userId } = req.body || {};
    if (!message) return res.status(400).json({ error: 'message required' });

    const key = userId || req.ip;
    if (!rateLimit(key)) return res.status(429).json({ error: 'rate_limited' });

    const cacheKey = `${key}:${message}`;
    const cached = cache.get(cacheKey);
    if (cached) return res.json({ reply: cached, cached: true });

    if (!STUDIO_API_URL || !STUDIO_API_KEY) {
      return res.status(500).json({ error: 'server not configured (STUDIO_API_URL/STUDIO_API_KEY)' });
    }

    // Build request for Generative API (Google AI Studio / Gemini)
    const payload = {
      contents: [
        {
          role: 'user',
          parts: [{ text: message }]
        }
      ],
      generationConfig: {
        maxOutputTokens: 500,
        temperature: 0.7
      },
      safetySettings: [
        { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' },
        { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'BLOCK_MEDIUM_AND_ABOVE' }
      ]
    };

    const response = await axios.post(`${STUDIO_API_URL}?key=${STUDIO_API_KEY}`, payload, {
      headers: { 'Content-Type': 'application/json' },
      timeout: 20000
    });

    // Extract reply from Generative API response format
    let replyText = '';
    if (response.data && response.data.candidates && response.data.candidates.length > 0) {
      const candidate = response.data.candidates[0];
      if (candidate.content && candidate.content.parts && candidate.content.parts.length > 0) {
        replyText = candidate.content.parts[0].text;
      }
    }
    if (!replyText) {
      replyText = 'Sorry, I could not generate a response. Please try again.';
    }

    cache.set(cacheKey, replyText);
    return res.json({ reply: replyText, cached: false });
  } catch (err) {
    console.error('chat error', err?.toString(), err?.response?.data);
    return res.status(500).json({ error: 'internal_error', detail: err?.toString() });
  }
});

// ================== FIREBASE CLOUD MESSAGING NOTIFICATIONS ==================

// Initialize Firebase Admin
const admin = require('firebase-admin');
try {
  admin.initializeApp();
} catch (e) {
  console.warn('Firebase admin already initialized');
}

// Send push notification using FCM
async function sendPushNotification(token, title, body, data = {}) {
  const message = {
    notification: { title, body },
    data,
    token,
    android: {
      priority: 'high',
      notification: { channelId: 'alert_lauk_channel', priority: 'high', sound: 'default' },
    },
    apns: { payload: { aps: { sound: 'default', badge: 1 } } },
  };
  try {
    await admin.messaging().send(message);
    return true;
  } catch (error) {
    console.error('Error sending notification:', error);
    return false;
  }
}

// Send to multiple tokens
async function sendToMultipleTokens(tokens, title, body, data = {}) {
  const messages = tokens.map(token => ({
    notification: { title, body },
    data,
    token,
    android: { priority: 'high' },
    apns: { payload: { aps: { sound: 'default' } } },
  }));
  try {
    const response = await admin.messaging().sendAll(messages);
    console.log(`Sent ${response.successCount} notifications`);
    return response;
  } catch (error) {
    console.error('Error sending bulk notifications:', error);
    return null;
  }
}

// POST /sendSOSNotification - Send SOS alert to all admins
app.post('/sendSOSNotification', async (req, res) => {
  try {
    const { userName, location, reportId, timestamp } = req.body || {};
    console.log('SOS Alert:', { userName, location, reportId });

    const db = admin.firestore();
    const adminsSnapshot = await db.collection('users').where('role', '==', 'admin').get();

    const adminTokens = [];
    adminsSnapshot.forEach(doc => {
      const token = doc.data().fcmToken;
      if (token) adminTokens.push(token);
    });

    if (adminTokens.length === 0) {
      return res.json({ success: true, message: 'No admins to notify' });
    }

    const title = '🚨 SOS ALERT - IMMEDIATE ACTION REQUIRED';
    const body = `User ${userName || 'Unknown'} triggered SOS at ${location || 'Unknown location'}. Report: ${reportId || 'N/A'}`;
    const data = { type: 'sos_alert', reportId: reportId || '', userName: userName || '', location: location || '' };

    await sendToMultipleTokens(adminTokens, title, body, data);
    return res.json({ success: true, adminsNotified: adminTokens.length });
  } catch (err) {
    console.error('SOS notification error:', err);
    return res.status(500).json({ error: 'sos_error', detail: err.toString() });
  }
});

// POST /notifyAdminsOfNewReport - Notify admins of new report
app.post('/notifyAdminsOfNewReport', async (req, res) => {
  try {
    const { reportId, reportType, location, userName } = req.body || {};
    const db = admin.firestore();
    const adminsSnapshot = await db.collection('users').where('role', '==', 'admin').get();

    const adminTokens = [];
    adminsSnapshot.forEach(doc => {
      const token = doc.data().fcmToken;
      if (token) adminTokens.push(token);
    });

    if (adminTokens.length === 0) {
      return res.json({ success: true, message: 'No admins to notify' });
    }

    const title = '📋 New Incident Report';
    const body = `${reportType}: ${userName || 'User'} at ${location || 'Unknown location'}`;
    const data = { type: 'new_report', reportId: reportId || '', reportType: reportType || '' };

    await sendToMultipleTokens(adminTokens, title, body, data);
    return res.json({ success: true, adminsNotified: adminTokens.length });
  } catch (err) {
    console.error('New report notification error:', err);
    return res.status(500).json({ error: 'new_report_error', detail: err.toString() });
  }
});

// POST /notifyUserOfStatusUpdate - Notify user of status change
app.post('/notifyUserOfStatusUpdate', async (req, res) => {
  try {
    const { userToken, reportId, newStatus, reportType, adminNote } = req.body || {};
    if (!userToken) return res.status(400).json({ error: 'userToken required' });

    const statusText = { pending: 'Pending Review', investigating: 'Being Investigated', resolved: 'Resolved', rejected: 'Rejected' }[newStatus?.toLowerCase()] || newStatus;

    const title = '📱 Report Status Update';
    const body = `Your ${reportType || 'report'} is now: ${statusText}${adminNote ? '. Note: ' + adminNote : ''}`;
    const data = { type: 'status_update', reportId: reportId || '', newStatus: newStatus || '' };

    await sendPushNotification(userToken, title, body, data);
    return res.json({ success: true });
  } catch (err) {
    console.error('Status update notification error:', err);
    return res.status(500).json({ error: 'status_error', detail: err.toString() });
  }
});

// POST /sendEmergencyBroadcast - Emergency broadcast to all users
app.post('/sendEmergencyBroadcast', async (req, res) => {
  try {
    const { title, message, adminId } = req.body || {};
    if (!title || !message) return res.status(400).json({ error: 'title and message required' });

    const db = admin.firestore();
    const usersSnapshot = await db.collection('users').get();

    const userTokens = [];
    usersSnapshot.forEach(doc => {
      const token = doc.data().fcmToken;
      if (token) userTokens.push(token);
    });

    if (userTokens.length === 0) {
      return res.json({ success: true, message: 'No users to notify' });
    }

    const broadcastTitle = `🚨 EMERGENCY: ${title}`;
    const data = { type: 'emergency_broadcast', adminId: adminId || '' };

    await sendToMultipleTokens(userTokens, broadcastTitle, message, data);
    return res.json({ success: true, usersNotified: userTokens.length });
  } catch (err) {
    console.error('Emergency broadcast error:', err);
    return res.status(500).json({ error: 'broadcast_error', detail: err.toString() });
  }
});

// POST /vision-analyze { imageUrl, reportId }
app.post('/vision-analyze', async (req, res) => {
  try {
    const { imageUrl, reportId } = req.body || {};
    if (!imageUrl || !reportId) return res.status(400).json({ error: 'imageUrl and reportId required' });

    const VISION_API_KEY = process.env.VISION_API_KEY;
    if (!VISION_API_KEY) return res.status(500).json({ error: 'VISION_API_KEY not configured' });

    const visionPayload = {
      requests: [{ image: { source: { imageUri: imageUrl } }, features: [{ type: 'LABEL_DETECTION', maxResults: 10 }, { type: 'OBJECT_LOCALIZATION', maxResults: 10 }] }]
    };

    const visionResp = await axios.post(`https://vision.googleapis.com/v1/images:annotate?key=${VISION_API_KEY}`, visionPayload, { headers: { 'Content-Type': 'application/json' }, timeout: 20000 });
    const annotations = ((visionResp.data || {}).responses || [])[0] || {};
    const labels = (annotations.labelAnnotations || []).map(l => ({ description: l.description, score: l.score }));
    const objects = (annotations.localizedObjectAnnotations || []).map(o => ({ name: o.name, score: o.score }));

    const db = admin.firestore();
    const snapshot = await db.collection('reports').where('ID', '==', reportId).limit(1).get();
    if (!snapshot.empty) {
      await snapshot.docs[0].ref.update({ ImageLabels: labels, ImageObjects: objects, ImageURL: imageUrl, ImageAnalyzedAt: admin.firestore.FieldValue.serverTimestamp() });
    }

    return res.json({ success: true, labels, objects });
  } catch (err) {
    console.error('vision analyze error:', err);
    return res.status(500).json({ error: 'vision_error', detail: err.toString() });
  }
});

// ================== GOOGLE MAPS API PROXY (for Flutter Web CORS) ==================

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY || 'AIzaSyDZoFA1X_wSHpSZbD94758aOVuENg8xMUI';

// GET /maps/autocomplete?input=...
app.get('/maps/autocomplete', async (req, res) => {
  try {
    const { input } = req.query;
    if (!input) return res.status(400).json({ error: 'input required' });
    const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(input)}&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url, { timeout: 10000 });
    return res.json(response.data);
  } catch (err) {
    console.error('autocomplete proxy error:', err?.toString());
    return res.status(500).json({ error: 'autocomplete_proxy_error', detail: err?.toString() });
  }
});

// GET /maps/geocode?address=...
app.get('/maps/geocode', async (req, res) => {
  try {
    const { address } = req.query;
    if (!address) return res.status(400).json({ error: 'address required' });
    const url = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${GOOGLE_MAPS_API_KEY}`;
    const response = await axios.get(url, { timeout: 10000 });
    return res.json(response.data);
  } catch (err) {
    console.error('geocode proxy error:', err?.toString());
    return res.status(500).json({ error: 'geocode_proxy_error', detail: err?.toString() });
  }
});

// GET /maps/directions?origin=...&destination=...&mode=...&alternatives=...
app.get('/maps/directions', async (req, res) => {
  try {
    const { origin, destination, mode, alternatives } = req.query;
    if (!origin || !destination) return res.status(400).json({ error: 'origin and destination required' });
    let url = `https://maps.googleapis.com/maps/api/directions/json?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}&key=${GOOGLE_MAPS_API_KEY}`;
    if (mode) url += `&mode=${encodeURIComponent(mode)}`;
    if (alternatives) url += `&alternatives=${encodeURIComponent(alternatives)}`;
    const response = await axios.get(url, { timeout: 15000 });
    return res.json(response.data);
  } catch (err) {
    console.error('directions proxy error:', err?.toString());
    return res.status(500).json({ error: 'directions_proxy_error', detail: err?.toString() });
  }
});

const PORT = process.env.PORT || 8080;
if (require.main === module) {
  app.listen(PORT, () => console.log(`Server listening on ${PORT}`));
}

module.exports = app;
