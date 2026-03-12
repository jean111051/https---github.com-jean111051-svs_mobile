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
    const body = req.body || {};
    if (!body.name || !body.contact || !body.emergencyType || !body.severity || !body.gps) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
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
