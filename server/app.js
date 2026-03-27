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
    reportId: String,
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
    status: {
      type: String,
      default: 'new',
    },
    dispatcherUsername: {
      type: String,
      default: '',
    },
    dispatcherName: {
      type: String,
      default: '',
    },
    claimedByUsername: {
      type: String,
      default: '',
    },
    claimedByName: {
      type: String,
      default: '',
    },
    claimedAt: {
      type: Date,
      default: null,
    },
    assignedToUsername: {
      type: String,
      default: '',
    },
    assignedToName: {
      type: String,
      default: '',
    },
    assignedAt: {
      type: Date,
      default: null,
    },
    passCount: {
      type: Number,
      default: 0,
    },
    lastPassedByUsername: {
      type: String,
      default: '',
    },
    lastPassedByName: {
      type: String,
      default: '',
    },
    lastPassedAt: {
      type: Date,
      default: null,
    },
  },
  { timestamps: true }
);

const panicSchema = new mongoose.Schema(
  {
    reportId: String,
    contact: String,
    gps: String,
    barangay: String,
    landmark: String,
    street: String,
    status: {
      type: String,
      default: 'new',
    },
    dispatcherUsername: {
      type: String,
      default: '',
    },
    dispatcherName: {
      type: String,
      default: '',
    },
    claimedByUsername: {
      type: String,
      default: '',
    },
    claimedByName: {
      type: String,
      default: '',
    },
    claimedAt: {
      type: Date,
      default: null,
    },
    assignedToUsername: {
      type: String,
      default: '',
    },
    assignedToName: {
      type: String,
      default: '',
    },
    assignedAt: {
      type: Date,
      default: null,
    },
    passCount: {
      type: Number,
      default: 0,
    },
    lastPassedByUsername: {
      type: String,
      default: '',
    },
    lastPassedByName: {
      type: String,
      default: '',
    },
    lastPassedAt: {
      type: Date,
      default: null,
    },
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

function normalizeReportId(value) {
  const compact = String(value || '').trim().replace(/\s+/g, '');
  if (/^[a-f0-9]{24}$/i.test(compact)) {
    return compact.toLowerCase();
  }
  return compact.toUpperCase();
}

function escapeRegex(value) {
  return String(value || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildTrackLookupWhere(id) {
  const raw = String(id || '').trim();
  const normalized = normalizeReportId(id);
  if (!raw && !normalized) return { reportId: '' };

  const clauses = [];
  const pushReportId = (value) => {
    const text = String(value || '').trim();
    if (!text) return;
    clauses.push({ reportId: text });
    clauses.push({ reportId: { $regex: `^${escapeRegex(text)}$`, $options: 'i' } });
  };

  pushReportId(raw);
  if (normalized != raw) pushReportId(normalized);

  if (mongoose.Types.ObjectId.isValid(raw)) {
    clauses.push({ _id: raw.toLowerCase() });
  }
  if (normalized && normalized !== raw && mongoose.Types.ObjectId.isValid(normalized)) {
    clauses.push({ _id: normalized });
  }

  return clauses.length == 1 ? clauses[0] : { $or: clauses };
}

async function nextPublicId(prefix, Model) {
  const safePrefix = String(prefix || '').trim().toUpperCase() || 'RPT';
  let seq = (await Model.countDocuments()) + 1;
  while (true) {
    const candidate = `${safePrefix}-${String(seq).padStart(4, '0')}`;
    const exists = await Model.exists({ reportId: candidate });
    if (!exists) return candidate;
    seq += 1;
  }
}

function humanizeStatus(status) {
  const raw = String(status || '').trim().toLowerCase();
  if (!raw) return 'Pending';
  return raw
    .split('-')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function pickFirst(values) {
  for (const value of values) {
    const text = String(value || '').trim();
    if (text) return text;
  }
  return '';
}

function buildPublicLocationLabel(report) {
  return pickFirst([
    [report && report.street, report && report.landmark, report && report.barangay]
      .filter(Boolean)
      .join(', '),
    [report && report.landmark, report && report.barangay].filter(Boolean).join(', '),
    report && report.barangay,
    report && report.gps ? `GPS ${report.gps}` : '',
    'Location pending confirmation',
  ]);
}

function buildTrackPayload(report, { fallbackEmergencyType = 'Emergency Report', fallbackReporter = 'Reporter' } = {}) {
  const currentDispatcherUsername = pickFirst([
    report && report.assignedToUsername,
    report && report.claimedByUsername,
    report && report.dispatcherUsername,
  ]);
  const currentDispatcherName = pickFirst([
    report && report.assignedToName,
    report && report.claimedByName,
    report && report.dispatcherName,
    currentDispatcherUsername,
  ]);
  const currentDispatcherDisplay = pickFirst([
    currentDispatcherName,
    currentDispatcherUsername,
    'Waiting for dispatcher',
  ]);
  const lastPassedBy = pickFirst([
    report && report.lastPassedByName,
    report && report.lastPassedByUsername,
  ]);
  const claimedBy = pickFirst([
    report && report.claimedByName,
    report && report.claimedByUsername,
  ]);

  return {
    id: String((report && (report.reportId || report.id || report._id)) || '').trim(),
    status: String((report && report.status) || 'new').trim().toLowerCase(),
    statusLabel: humanizeStatus(report && report.status),
    reporterName: String((report && report.name) || '').trim() || fallbackReporter,
    emergencyType:
      String((report && report.emergencyType) || '').trim() || fallbackEmergencyType,
    currentDispatcher: currentDispatcherDisplay,
    dispatcherUsername: currentDispatcherUsername,
    dispatcherName: currentDispatcherName,
    claimedByUsername: String((report && report.claimedByUsername) || '').trim(),
    claimedByName: String((report && report.claimedByName) || '').trim(),
    claimedBy,
    assignedToUsername: String((report && report.assignedToUsername) || '').trim(),
    assignedToName: String((report && report.assignedToName) || '').trim(),
    passCount: Math.max(0, Number((report && report.passCount) || 0) || 0),
    lastPassedByUsername: String((report && report.lastPassedByUsername) || '').trim(),
    lastPassedByName: String((report && report.lastPassedByName) || '').trim(),
    lastPassedBy,
    submittedAt:
      (report && (report.createdAt || report.timestamp))
        ? new Date(report.createdAt || report.timestamp).toISOString()
        : '',
    claimedAt: report && report.claimedAt ? new Date(report.claimedAt).toISOString() : '',
    assignedAt: report && report.assignedAt ? new Date(report.assignedAt).toISOString() : '',
    lastPassedAt:
      report && report.lastPassedAt ? new Date(report.lastPassedAt).toISOString() : '',
    location: buildPublicLocationLabel(report),
    locationParts: {
      barangay: String((report && report.barangay) || '').trim(),
      landmark: String((report && report.landmark) || '').trim(),
      street: String((report && report.street) || '').trim(),
      gps: String((report && report.gps) || '').trim(),
    },
  };
}

async function findTrackReport(id) {
  const reportLookup = buildTrackLookupWhere(id);
  const report = await Report.findOne(reportLookup).lean();
  if (report) {
    return buildTrackPayload(report);
  }

  const panicLookup = buildTrackLookupWhere(id);
  const panic = await Panic.findOne(panicLookup).lean();
  if (!panic) return null;

  return buildTrackPayload(
    {
      ...panic,
      name: '',
      emergencyType: 'Panic SOS',
    },
    {
      fallbackEmergencyType: 'Panic SOS',
      fallbackReporter: 'SOS Reporter',
    }
  );
}

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
    const reportId = await nextPublicId('RPT', Report);
    const report = await Report.create({
      ...body,
      reportId,
      status: 'new',
    });
    res.json({ success: true, id: report.reportId || report._id.toString() });
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
    const reportId = await nextPublicId('SOS', Panic);
    const panic = await Panic.create({
      ...body,
      reportId,
      status: 'new',
    });
    res.json({ success: true, id: panic.reportId || panic._id.toString() });
  } catch (err) {
    console.error('Panic error:', err);
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

async function resolveTrackDocument(id) {
  const where = buildTrackLookupWhere(id);

  const report = await Report.findOne(where);
  if (report) return { model: Report, doc: report };

  const panic = await Panic.findOne(where);
  if (panic) return { model: Panic, doc: panic };

  return null;
}

function cleanPerson(value) {
  return String(value || '').trim();
}

async function saveTrackMutation(resolved, patch) {
  Object.assign(resolved.doc, patch);
  await resolved.doc.save();
  return buildTrackPayload(resolved.doc.toObject());
}

app.patch('/api/track/:id/claim', async (req, res) => {
  try {
    await ensureDb();
    const resolved = await resolveTrackDocument(req.params.id);
    if (!resolved) {
      return res.status(404).json({ success: false, error: 'Report not found' });
    }

    const username = cleanPerson(req.body && req.body.username);
    const name = cleanPerson(req.body && req.body.name);
    if (!username && !name) {
      return res.status(400).json({
        success: false,
        error: 'Dispatcher username or name is required',
      });
    }

    const claimedUsername =
      cleanPerson(resolved.doc.claimedByUsername) || username;
    const claimedName = cleanPerson(resolved.doc.claimedByName) || name;
    const claimedAt = resolved.doc.claimedAt || new Date();

    const report = await saveTrackMutation(resolved, {
      status: cleanPerson(req.body && req.body.status) || 'verifying',
      dispatcherUsername: username || claimedUsername,
      dispatcherName: name || claimedName,
      claimedByUsername: claimedUsername,
      claimedByName: claimedName,
      claimedAt,
      assignedToUsername: username || claimedUsername,
      assignedToName: name || claimedName,
      assignedAt: new Date(),
    });

    return res.json({ success: true, report });
  } catch (err) {
    console.error('Track claim error:', err);
    return res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.patch('/api/track/:id/assign', async (req, res) => {
  try {
    await ensureDb();
    const resolved = await resolveTrackDocument(req.params.id);
    if (!resolved) {
      return res.status(404).json({ success: false, error: 'Report not found' });
    }

    const username = cleanPerson(req.body && req.body.username);
    const name = cleanPerson(req.body && req.body.name);
    if (!username && !name) {
      return res.status(400).json({
        success: false,
        error: 'Dispatcher username or name is required',
      });
    }

    const report = await saveTrackMutation(resolved, {
      status: cleanPerson(req.body && req.body.status) || 'dispatched',
      dispatcherUsername: username,
      dispatcherName: name,
      assignedToUsername: username,
      assignedToName: name,
      assignedAt: new Date(),
    });

    return res.json({ success: true, report });
  } catch (err) {
    console.error('Track assign error:', err);
    return res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.patch('/api/track/:id/pass', async (req, res) => {
  try {
    await ensureDb();
    const resolved = await resolveTrackDocument(req.params.id);
    if (!resolved) {
      return res.status(404).json({ success: false, error: 'Report not found' });
    }

    const fromUsername = cleanPerson(req.body && req.body.fromUsername);
    const fromName = cleanPerson(req.body && req.body.fromName);
    const toUsername = cleanPerson(req.body && req.body.toUsername);
    const toName = cleanPerson(req.body && req.body.toName);

    const nextPassCount = Math.max(0, Number(resolved.doc.passCount) || 0) + 1;
    const report = await saveTrackMutation(resolved, {
      status: cleanPerson(req.body && req.body.status) || 'dispatched',
      dispatcherUsername: toUsername || resolved.doc.dispatcherUsername || '',
      dispatcherName: toName || resolved.doc.dispatcherName || '',
      assignedToUsername: toUsername || resolved.doc.assignedToUsername || '',
      assignedToName: toName || resolved.doc.assignedToName || '',
      assignedAt: new Date(),
      passCount: nextPassCount,
      lastPassedByUsername: fromUsername,
      lastPassedByName: fromName,
      lastPassedAt: new Date(),
    });

    return res.json({ success: true, report });
  } catch (err) {
    console.error('Track pass error:', err);
    return res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

app.patch('/api/track/:id/status', async (req, res) => {
  try {
    await ensureDb();
    const resolved = await resolveTrackDocument(req.params.id);
    if (!resolved) {
      return res.status(404).json({ success: false, error: 'Report not found' });
    }

    const status = cleanPerson(req.body && req.body.status).toLowerCase();
    if (!status) {
      return res.status(400).json({
        success: false,
        error: 'Status is required',
      });
    }

    const report = await saveTrackMutation(resolved, { status });
    return res.json({ success: true, report });
  } catch (err) {
    console.error('Track status error:', err);
    return res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
});

async function handleTrackLookup(req, res, id) {
  try {
    await ensureDb();
    const report = await findTrackReport(id);
    if (!report) {
      return res.status(404).json({
        success: false,
        error: 'Report ID not found. Check the ID and try again.',
      });
    }
    res.json({
      success: true,
      report,
    });
  } catch (err) {
    console.error('Track lookup error:', err);
    res.status(500).json({
      success: false,
      error: err instanceof Error ? err.message : 'Server error',
    });
  }
}

app.get('/api/track', async (req, res) => {
  return handleTrackLookup(req, res, req.query.id);
});

app.get('/api/track/:id', async (req, res) => {
  return handleTrackLookup(req, res, req.params.id);
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
