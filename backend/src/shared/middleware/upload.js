const multer = require('multer');
const path = require('path');
const { AppError } = require('./errorHandler');

// Store uploads in memory — we stream to Supabase Storage (prod) or disk (dev)
const storage = multer.memoryStorage();

const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'application/pdf'];
const MAX_FILE_SIZE_MB = 5;

const fileFilter = (req, file, cb) => {
  if (!ALLOWED_MIME_TYPES.includes(file.mimetype)) {
    return cb(new AppError('Only JPEG, PNG, and PDF files are allowed.', 400), false);
  }
  cb(null, true);
};

const upload = multer({
  storage,
  limits: { fileSize: MAX_FILE_SIZE_MB * 1024 * 1024 },
  fileFilter,
});

/**
 * Save uploaded file buffer to Supabase Storage (production) or local disk (dev).
 *
 * Production path (SUPABASE_STORAGE_BUCKET is set):
 *   - Uploads to the configured Supabase Storage bucket.
 *   - Returns the public URL — permanent, survives redeploys, globally accessible.
 *   - Bucket must be created in Supabase dashboard (Storage → New bucket).
 *   - Recommended: set bucket to private + use signed URLs for sensitive docs.
 *
 * Development path (SUPABASE_STORAGE_BUCKET not set):
 *   - Falls back to local disk under /uploads/<subfolder>/<filename>.
 *   - Served via express.static('/uploads') mounted in app.js (dev only).
 *   - Files are lost on process restart — acceptable for local testing.
 *
 * @param {Buffer}  fileBuffer   Raw file bytes from multer memoryStorage
 * @param {string}  originalName Original filename (used to extract extension)
 * @param {string}  subfolder    Logical grouping e.g. 'documents', 'profiles'
 * @returns {Promise<string>}    Public URL or local path
 */
const saveFile = async (fileBuffer, originalName, subfolder = 'documents') => {
  const bucket = process.env.SUPABASE_STORAGE_BUCKET;

  // ── Production: Supabase Storage ─────────────────────────────────────────────
  if (bucket) {
    const { supabase } = require('../db/client');

    const ext = path.extname(originalName) || '.jpg';
    const filename = `${subfolder}/${Date.now()}_${Math.random().toString(36).substring(2, 9)}${ext}`;

    const { error } = await supabase.storage
      .from(bucket)
      .upload(filename, fileBuffer, {
        contentType: _mimeFromExt(ext),
        upsert: false,
      });

    if (error) {
      throw new AppError(`File upload failed: ${error.message}`, 500);
    }

    // Return the public URL — works for public buckets.
    // For private buckets, swap this for supabase.storage.from(bucket).createSignedUrl(...)
    const { data } = supabase.storage.from(bucket).getPublicUrl(filename);
    return data.publicUrl;
  }

  // ── Development: local disk ───────────────────────────────────────────────────
  const fs = require('fs');
  const uploadsDir = path.join(process.cwd(), 'uploads');
  const dir = path.join(uploadsDir, subfolder);

  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const ext = path.extname(originalName) || '.jpg';
  const filename = `${Date.now()}_${Math.random().toString(36).substring(2, 9)}${ext}`;
  const filePath = path.join(dir, filename);

  fs.writeFileSync(filePath, fileBuffer);

  // Return a relative URL served by express.static in app.js (dev only)
  return `/uploads/${subfolder}/${filename}`;
};

const _mimeFromExt = (ext) => {
  const map = { '.pdf': 'application/pdf', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg' };
  return map[ext.toLowerCase()] || 'application/octet-stream';
};

/**
 * Handle multer errors gracefully
 */
const handleUploadError = (err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return next(new AppError(`File too large. Maximum size is ${MAX_FILE_SIZE_MB}MB.`, 400));
    }
    return next(new AppError(`Upload error: ${err.message}`, 400));
  }
  next(err);
};

module.exports = { upload, saveFile, handleUploadError };
