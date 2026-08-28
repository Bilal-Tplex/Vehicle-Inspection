import path from 'node:path';

import cors from 'cors';
import express from 'express';

import { config, ROOT } from './config.js';
import { getDatabase } from './db/database.js';
import { seed } from './db/seed.js';
import { errorHandler, notFoundHandler } from './middleware/errors.js';
import { authRouter } from './routes/auth.js';
import {
  adminInspectionRouter,
  inspectionRouter,
  mediaRouter,
} from './routes/inspections.js';
import { reportRouter } from './routes/reports.js';
import { adminTemplateRouter, templateRouter } from './routes/templates.js';
import { userRouter } from './routes/users.js';

const app = express();

// The dashboard is served from this same origin, but the mobile app is not —
// on an emulator it reaches the host as 10.0.2.2, and on a handset by LAN IP.
app.use(cors());
app.use(express.json({ limit: '5mb' }));

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

const api = express.Router();

// Endpoints the mobile app calls. These four are the entire contract the
// Flutter `ApiClient` interface describes.
api.use('/auth', authRouter);
api.use('/templates', templateRouter);
api.use('/inspections', inspectionRouter);
api.use('/media', mediaRouter);

// Dashboard-only endpoints.
api.use('/admin/templates', adminTemplateRouter);
api.use('/admin/inspections', adminInspectionRouter);
api.use('/admin/users', userRouter);
api.use('/admin/reports', reportRouter);

api.get('/health', (_req, res) =>
  res.json({ ok: true, service: 'vehicle-inspection-api', time: new Date().toISOString() }),
);

app.use(config.apiPrefix, api);

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------

const publicDir = path.join(ROOT, 'public');
app.use(express.static(publicDir));

// The dashboard is a single-page app, so any non-API path returns the shell and
// lets client-side routing take over.
app.get(/^(?!\/v1).*/, (_req, res) => {
  res.sendFile(path.join(publicDir, 'index.html'));
});

app.use(notFoundHandler);
app.use(errorHandler);

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

getDatabase();
seed({ verbose: false });

app.listen(config.port, () => {
  console.log(`\n  Vehicle Inspection API + Admin Dashboard`);
  console.log(`  ────────────────────────────────────────`);
  console.log(`  Dashboard   http://localhost:${config.port}`);
  console.log(`  API         http://localhost:${config.port}${config.apiPrefix}`);
  console.log(`  Android     http://10.0.2.2:${config.port}${config.apiPrefix}  (emulator)`);
  console.log(`\n  admin@test.com / admin123\n`);
});
