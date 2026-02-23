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

// (vision analyze removed — using on-device ML Kit instead)

const PORT = process.env.PORT || 8080;
if (require.main === module) {
  app.listen(PORT, () => console.log(`AI proxy listening on ${PORT}`));
}

module.exports = app;

// Initialize Firebase Admin for Firestore updates (used by vision analyze)
const admin = require('firebase-admin');
try {
  admin.initializeApp();
} catch (e) {
  console.warn('Firebase admin already initialized');
}

// POST /vision-analyze { imageUrl, reportId }
app.post('/vision-analyze', async (req, res) => {
  try {
    const { imageUrl, reportId } = req.body || {};
    if (!imageUrl || !reportId) return res.status(400).json({ error: 'imageUrl and reportId required' });

    const VISION_API_KEY = process.env.VISION_API_KEY;
    if (!VISION_API_KEY) return res.status(500).json({ error: 'VISION_API_KEY not configured' });

    const visionPayload = {
      requests: [
        {
          image: { source: { imageUri: imageUrl } },
          features: [
            { type: 'LABEL_DETECTION', maxResults: 10 },
            { type: 'OBJECT_LOCALIZATION', maxResults: 10 },
            { type: 'SAFE_SEARCH_DETECTION', maxResults: 10 }
          ]
        }
      ]
    };

    const visionResp = await axios.post(`https://vision.googleapis.com/v1/images:annotate?key=${VISION_API_KEY}`, visionPayload, { headers: { 'Content-Type': 'application/json' }, timeout: 20000 });
    const annotations = ((visionResp.data || {}).responses || [])[0] || {};

    const labels = (annotations.labelAnnotations || []).map(l => ({ description: l.description, score: l.score }));
    const objects = (annotations.localizedObjectAnnotations || []).map(o => ({ name: o.name, score: o.score }));
    const safeSearch = annotations.safeSearchAnnotation || {};

    // Update Firestore report document (match by custom ID field 'ID')
    const db = admin.firestore();
    const reportsRef = db.collection('reports');
    const snapshot = await reportsRef.where('ID', '==', reportId).limit(1).get();
    if (!snapshot.empty) {
      const docRef = snapshot.docs[0].ref;
      await docRef.update({
        ImageLabels: labels,
        ImageObjects: objects,
        SafeSearch: safeSearch,
        ImageURL: imageUrl,
        ImageAnalyzedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return res.json({ success: true, labels, objects, safeSearch });
  } catch (err) {
    console.error('vision analyze error', err?.toString(), err?.response?.data);
    return res.status(500).json({ error: 'vision_error', detail: err?.toString() });
  }
});
