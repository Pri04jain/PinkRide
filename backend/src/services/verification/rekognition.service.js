const {
  RekognitionClient,
  CreateCollectionCommand,
  IndexFacesCommand,
  SearchFacesByImageCommand,
  DeleteFacesCommand,
  DetectFacesCommand,
} = require('@aws-sdk/client-rekognition');

const { AppError } = require('../../shared/middleware/errorHandler');

const rekognitionClient = new RekognitionClient({
  region: process.env.AWS_REGION || 'ap-south-1',
  credentials: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  },
});

const COLLECTION_ID = process.env.AWS_REKOGNITION_COLLECTION_ID || 'pinkride-faces';
const MATCH_THRESHOLD = 90;

// ─── Collection Setup ─────────────────────────────────────────────────────────

const ensureCollection = async () => {
  try {
    await rekognitionClient.send(new CreateCollectionCommand({ CollectionId: COLLECTION_ID }));
    console.log('Rekognition collection created: ' + COLLECTION_ID);
  } catch (err) {
    if (err.name === 'ResourceAlreadyExistsException') return;
    throw err;
  }
};

// ─── Liveness / Face Detection ────────────────────────────────────────────────

const detectAndValidateFace = async (imageBuffer) => {
  const command = new DetectFacesCommand({
    Image: { Bytes: imageBuffer },
    Attributes: ['ALL'],
  });

  const response = await rekognitionClient.send(command);
  const faces = response.FaceDetails || [];

  if (faces.length === 0) {
    return { faceDetected: false, reason: 'No face detected in the image.' };
  }
  if (faces.length > 1) {
    return { faceDetected: false, reason: 'Multiple faces detected. Please capture only your face.' };
  }

  const face = faces[0];

  if (face.Confidence < 90) {
    return { faceDetected: false, reason: 'Face not clearly visible. Please ensure good lighting.' };
  }

  const leftEyeOpen = face.EyesOpen && face.EyesOpen.Value === true && face.EyesOpen.Confidence > 85;
  const rightEyeOpen = face.EyesOpen && face.EyesOpen.Value === true && face.EyesOpen.Confidence > 85;

  if (!leftEyeOpen || !rightEyeOpen) {
    return { faceDetected: false, reason: 'Please keep your eyes open and look at the camera.' };
  }

  if (face.Sunglasses && face.Sunglasses.Value === true && face.Sunglasses.Confidence > 85) {
    return { faceDetected: false, reason: 'Please remove sunglasses for verification.' };
  }

  const pose = face.Pose || {};
  if (Math.abs(pose.Yaw || 0) > 30 || Math.abs(pose.Pitch || 0) > 30) {
    return { faceDetected: false, reason: 'Please face the camera directly.' };
  }

  const quality = face.Quality || {};
  if ((quality.Brightness || 0) < 30) {
    return { faceDetected: false, reason: 'Image too dark. Please move to a brighter area.' };
  }
  if ((quality.Sharpness || 0) < 30) {
    return { faceDetected: false, reason: 'Image blurry. Please hold the camera steady.' };
  }

  return {
    faceDetected: true,
    livenessScore: face.Confidence,
    details: {
      confidence: face.Confidence,
      ageRange: face.AgeRange,
      quality: face.Quality,
    },
  };
};

// ─── Index Face (Registration) ────────────────────────────────────────────────

const indexFace = async (imageBuffer, userId) => {
  const command = new IndexFacesCommand({
    CollectionId: COLLECTION_ID,
    Image: { Bytes: imageBuffer },
    ExternalImageId: userId,
    DetectionAttributes: ['DEFAULT'],
    MaxFaces: 1,
    QualityFilter: 'HIGH',
  });

  const response = await rekognitionClient.send(command);
  const records = response.FaceRecords || [];

  if (records.length === 0) {
    const unindexed = response.UnindexedFaces || [];
    const reason = (unindexed[0] && unindexed[0].Reasons && unindexed[0].Reasons[0]) || 'Face quality too low to index.';
    throw new AppError('Face could not be registered: ' + reason, 422);
  }

  const face = records[0].Face;
  return { faceId: face.FaceId, confidence: face.Confidence };
};

// ─── Compare Face (Pre-ride verification) ────────────────────────────────────

const compareFace = async (imageBuffer, storedFaceId) => {
  const command = new SearchFacesByImageCommand({
    CollectionId: COLLECTION_ID,
    Image: { Bytes: imageBuffer },
    MaxFaces: 1,
    FaceMatchThreshold: MATCH_THRESHOLD,
  });

  let response;
  try {
    response = await rekognitionClient.send(command);
  } catch (err) {
    if (err.name === 'InvalidParameterException') {
      throw new AppError('No face detected in the selfie. Please try again.', 422);
    }
    throw err;
  }

  const matches = response.FaceMatches || [];

  if (matches.length === 0) {
    return { matched: false, similarity: 0, reason: 'Face does not match registered profile.' };
  }

  const topMatch = matches[0];
  const matchedFaceId = topMatch.Face && topMatch.Face.FaceId;
  const similarity = topMatch.Similarity || 0;

  if (matchedFaceId !== storedFaceId) {
    return { matched: false, similarity, reason: 'Face matched a different profile. Please contact support.' };
  }

  return { matched: true, similarity, faceId: matchedFaceId };
};

// ─── Delete Face (DPDP right to erasure) ─────────────────────────────────────

const deleteFace = async (faceId) => {
  await rekognitionClient.send(new DeleteFacesCommand({
    CollectionId: COLLECTION_ID,
    FaceIds: [faceId],
  }));
  return { deleted: true };
};

// ─── Dev Mock Mode ────────────────────────────────────────────────────────────
//
// Mock mode is controlled by the explicit FACE_VERIFICATION_MOCK=true env flag.
//
// Previously this relied on NODE_ENV !== 'production', which meant a production
// server started without NODE_ENV=production set would silently bypass all
// biometric checks. Now mock mode only activates when explicitly opted in,
// making the production-safe default not require any special configuration.
//
// Also: isMockMode() is now evaluated lazily (inside each exported wrapper)
// instead of once at module load time, so a misconfigured process can't get
// permanently locked into mock mode for its lifetime.

const isMockMode = () => process.env.FACE_VERIFICATION_MOCK === 'true';

const mockDetect = async () => ({ faceDetected: true, livenessScore: 99.5, details: { confidence: 99.5 } });
const mockIndex = async (buf, userId) => ({ faceId: 'mock-face-' + userId.substring(0, 8), confidence: 99.2 });
const mockCompare = async (buf, storedFaceId) => ({ matched: true, similarity: 98.7, faceId: storedFaceId });
const mockDelete = async () => ({ deleted: true });

module.exports = {
  ensureCollection,
  detectAndValidateFace: (buf) => isMockMode() ? mockDetect(buf) : detectAndValidateFace(buf),
  indexFace: (buf, userId) => isMockMode() ? mockIndex(buf, userId) : indexFace(buf, userId),
  compareFace: (buf, faceId) => isMockMode() ? mockCompare(buf, faceId) : compareFace(buf, faceId),
  deleteFace: (faceId) => isMockMode() ? mockDelete(faceId) : deleteFace(faceId),
  MATCH_THRESHOLD,
};
