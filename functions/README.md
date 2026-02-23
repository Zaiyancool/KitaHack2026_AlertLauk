# AlertLauk AI Proxy (Cloud Function)

Purpose
- Thin HTTP proxy that forwards chat messages to a configured Generative API (AI Studio / Generative API).
- Keeps API keys off the client, adds simple caching and rate-limiting for cost control.

Environment
- `STUDIO_API_URL` — full URL of the Generative endpoint (example: the Studio/Generative endpoint or exported endpoint URL).
- `STUDIO_API_KEY` — API key to use with the endpoint (or use Secret Manager and inject at deploy time).
- `MAX_PER_MINUTE` — optional, integer rate limit per user (defaults to 30).

Run locally (Node 18+)
```
cd functions
npm install
STUDIO_API_URL="https://your-studio-endpoint" STUDIO_API_KEY="YOUR_KEY" node index.js
```

Deploy to Cloud Functions (example using gcloud)
```
cd functions
gcloud functions deploy chatProxy \
  --runtime=nodejs18 \
  --trigger-http \
  --allow-unauthenticated \
  --set-env-vars=STUDIO_API_URL="https://...",STUDIO_API_KEY="..."
```

Notes
- This is a minimal prototype. For production: use Secret Manager, add authentication, persistent caching, and more robust rate-limiting (Redis), and adapt the request payload to the exact Generative API schema used.
