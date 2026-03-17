const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
require('dotenv').config();

const app = express();

app.use(cors());
app.use(express.json({ limit: '12mb' }));

const MONGODB_URI = process.env.MONGODB_URI || '';
const MONGODB_DB = process.env.MONGODB_DB || '';

let dbReady = false;
async function ensureDb() {
  if (dbReady) return;
  if (!MONGODB_URI) {
    throw new Error('MONGODB_URI is not set');
  }
  await mongoose.connect(MONGODB_URI, {
    dbName: MONGODB_DB || undefined,
  });
  dbReady = true;
}

const reportSchema = new mongoose.Schema(
  {
    name: String,
    contact: String,
    emergencyType: String,
    severity: String,
    barangay: String,
    landmark: String,
    street: String,
    description: String,
    gps: String,
    photo: String,
    photos: [String],
  },
  { timestamps: true }
);

const panicSchema = new mongoose.Schema(
  {
    contact: String,
    gps: String,
    barangay: String,
    landmark: String,
    street: String,
  },
  { timestamps: true }
);

const Report = mongoose.model('Report', reportSchema);
const Panic = mongoose.model('Panic', panicSchema);

function normalizePhotoFields(body) {
  if (!body || typeof body !== 'object') return body;
  const toStr = (v) => (typeof v === 'string' ? v.trim() : '');
  const isUrl = (v) => /^https?:\/\//i.test(v);
  const isData = (v) => /^data:image\/[a-z0-9.+-]+;base64,/i.test(v);
  const valid = (v) => isUrl(v) || isData(v);

  const photo = toStr(body.photo);
  const photos = Array.isArray(body.photos)
    ? body.photos.map(toStr).filter(valid)
    : [];

  const normalized = { ...body };
  if (photo && valid(photo)) {
    normalized.photo = photo;
  } else if (photos.length > 0) {
    normalized.photo = photos[0];
  } else {
    delete normalized.photo;
  }
  if (photos.length > 0) {
    normalized.photos = photos;
  } else {
    delete normalized.photos;
  }
  return normalized;
}

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

// Used by the Flutter app to probe if server is reachable
app.get('/report', (_req, res) => {
  res.status(200).send('OK');
});

app.post('/api/report', async (req, res) => {
  try {
    await ensureDb();
    let body = req.body || {};
    if (!body.name || !body.contact || !body.emergencyType || !body.severity || !body.gps) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    body = normalizePhotoFields(body);
    const report = await Report.create(body);
    res.json({ success: true, id: report._id.toString() });
  } catch (err) {
    console.error('Report error:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

app.post('/api/panic', async (req, res) => {
  try {
    await ensureDb();
    const body = req.body || {};
    if (!body.contact || !body.gps) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    const panic = await Panic.create(body);
    res.json({ success: true, id: panic._id.toString() });
  } catch (err) {
    console.error('Panic error:', err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// Simple reverse-geocode stub. Replace with real geocoder if needed.
app.get('/api/reverse-geocode', (_req, res) => {
  res.json({ barangay: '', landmark: '', street: '' });
});

module.exports = app;
