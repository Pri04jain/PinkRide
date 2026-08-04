const multer = require('multer');
const path = require('path');
const { AppError } = require('./errorHandler');

// Store uploads in memory — we'll stream to disk/S3 from the service layer
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
 * Save uploaded file buffer to local disk (dev) or return path for S3 (prod).
 * In MVP we store locally under /uploads. In production, swap this for S3.
 */
const fs = require('fs');
const uploadsDir = path.join(process.cwd(), 'uploads');

const saveFile = async (fileBuffer, originalName, subfolder = 'documents') => {
  const dir = path.join(uploadsDir, subfolder);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const ext = path.extname(originalName) || '.jpg';
  const filename = `${Date.now()}_${Math.random().toString(36).substring(2, 9)}${ext}`;
  const filePath = path.join(dir, filename);

  fs.writeFileSync(filePath, fileBuffer);

  // Return a relative path — in production this would be an S3 URL
  return `/uploads/${subfolder}/${filename}`;
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
