const path = require('path');
const express = require('express');
const cors = require('cors');
const mongoose = require('mongoose');
require('dotenv').config({ path: path.join(__dirname, '.env') });

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

const alertSchema = new mongoose.Schema(
  {
    title: String,
    message: String,
    disasterType: String,
    severity: String,
    active: {
      type: Boolean,
      default: true,
    },
    sentBy: String,
  },
  { timestamps: true }
);

const Report = mongoose.model('Report', reportSchema);
const Panic = mongoose.model('Panic', panicSchema);
const Alert = mongoose.model('Alert', alertSchema);

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
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
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
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.get('/api/alerts/latest', async (_req, res) => {
  try {
    await ensureDb();
    const alert = await Alert.findOne({ active: true }).sort({ createdAt: -1 });
    res.json({
      success: true,
      alert: alert
        ? {
            id: alert._id.toString(),
            title: alert.title || 'Emergency alert',
            message: alert.message || '',
            disasterType: alert.disasterType || 'General',
            severity: alert.severity || 'high',
            active: alert.active !== false,
            sentBy: alert.sentBy || '',
            createdAt: alert.createdAt,
            updatedAt: alert.updatedAt,
          }
        : null,
    });
  } catch (err) {
    console.error('Latest alert error:', err);
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.get('/api/alerts', async (req, res) => {
  try {
    await ensureDb();
    const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 100);
    const alerts = await Alert.find().sort({ createdAt: -1 }).limit(limit);
    res.json({
      success: true,
      alerts: alerts.map((alert) => ({
        id: alert._id.toString(),
        title: alert.title || 'Emergency alert',
        message: alert.message || '',
        disasterType: alert.disasterType || 'General',
        severity: alert.severity || 'high',
        active: alert.active !== false,
        sentBy: alert.sentBy || '',
        createdAt: alert.createdAt,
        updatedAt: alert.updatedAt,
      })),
    });
  } catch (err) {
    console.error('List alerts error:', err);
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.post('/api/alerts', async (req, res) => {
  try {
    await ensureDb();
    const body = req.body || {};
    const title = (body.title || '').toString().trim();
    const message = (body.message || '').toString().trim();
    const disasterType = (body.disasterType || body.type || 'General')
      .toString()
      .trim();
    const severity = (body.severity || 'high').toString().trim().toLowerCase();
    const sentBy = (body.sentBy || 'admin').toString().trim();
    const active = body.active !== false;

    if (!title && !message) {
      return res.status(400).json({
        success: false,
        error: 'Title or message is required',
      });
    }

    const alert = await Alert.create({
      title: title || `${disasterType} alert`,
      message: message || title,
      disasterType: disasterType || 'General',
      severity: severity || 'high',
      active,
      sentBy,
    });

    res.json({
      success: true,
      id: alert._id.toString(),
      alert: {
        id: alert._id.toString(),
        title: alert.title,
        message: alert.message,
        disasterType: alert.disasterType,
        severity: alert.severity,
        active: alert.active !== false,
        sentBy: alert.sentBy || '',
        createdAt: alert.createdAt,
        updatedAt: alert.updatedAt,
      },
    });
  } catch (err) {
    console.error('Create alert error:', err);
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.patch('/api/alerts/:id', async (req, res) => {
  try {
    await ensureDb();
    const body = req.body || {};
    const update = {};
    if ('title' in body) update.title = (body.title || '').toString().trim();
    if ('message' in body) {
      update.message = (body.message || '').toString().trim();
    }
    if ('disasterType' in body || 'type' in body) {
      update.disasterType = (body.disasterType || body.type || 'General')
        .toString()
        .trim();
    }
    if ('severity' in body) {
      update.severity = (body.severity || 'high').toString().trim().toLowerCase();
    }
    if ('active' in body) update.active = body.active !== false;
    if ('sentBy' in body) update.sentBy = (body.sentBy || '').toString().trim();

    const alert = await Alert.findByIdAndUpdate(req.params.id, update, {
      new: true,
    });
    if (!alert) {
      return res.status(404).json({ success: false, error: 'Alert not found' });
    }

    res.json({
      success: true,
      alert: {
        id: alert._id.toString(),
        title: alert.title || 'Emergency alert',
        message: alert.message || '',
        disasterType: alert.disasterType || 'General',
        severity: alert.severity || 'high',
        active: alert.active !== false,
        sentBy: alert.sentBy || '',
        createdAt: alert.createdAt,
        updatedAt: alert.updatedAt,
      },
    });
  } catch (err) {
    console.error('Update alert error:', err);
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

// Simple reverse-geocode stub. Replace with real geocoder if needed.
app.get('/api/reverse-geocode', (_req, res) => {
  res.json({ barangay: '', landmark: '', street: '' });
});

module.exports = app;
