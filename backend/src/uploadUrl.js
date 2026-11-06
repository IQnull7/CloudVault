const { randomUUID } = require("crypto");
const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");

const s3 = new S3Client({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const BUCKET = process.env.BUCKET_NAME;
const FILES_TABLE = process.env.FILES_TABLE;

const MAX_BYTES = 10 * 1024 * 1024; // 10 MB
const UPLOAD_URL_TTL_SECONDS = 300;
const PENDING_TTL_MS = 10 * 60 * 1000;
const ALLOWED_TYPES = new Set([
  "application/pdf",
  "image/png",
  "image/jpeg",
  "text/plain",
]);

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  let body;
  try {
    body = JSON.parse(event.body ?? "{}");
  } catch {
    return json(400, { error: "Body must be valid JSON" });
  }

  const { fileName, sizeBytes, contentType } = body;
  if (typeof fileName !== "string" || fileName.length < 1 || fileName.length > 255) {
    return json(400, { error: "fileName must be 1-255 characters" });
  }
  if (!Number.isInteger(sizeBytes) || sizeBytes < 1 || sizeBytes > MAX_BYTES) {
    return json(400, { error: `sizeBytes must be an integer from 1 to ${MAX_BYTES}` });
  }
  if (!ALLOWED_TYPES.has(contentType)) {
    return json(400, { error: "contentType not allowed" });
  }

  // The server decides the ID and the S3 key. The client never supplies either.
  const fileId = randomUUID();
  const s3Key = `uploads/${fileId}`;
  const now = Date.now();

  await ddb.send(
    new PutCommand({
      TableName: FILES_TABLE,
      Item: {
        fileId,
        status: "pending",
        pendingOwner: caller.email,
        fileName,
        declaredSize: sizeBytes,
        declaredType: contentType,
        pendingExpiresAt: now + PENDING_TTL_MS,
      },
      ConditionExpression: "attribute_not_exists(fileId)",
    })
  );

  // ContentType and ContentLength become signed headers, so S3 rejects an
  // upload whose type or length differs from what was declared here.
  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: s3Key,
      ContentType: contentType,
      ContentLength: sizeBytes,
    }),
    { expiresIn: UPLOAD_URL_TTL_SECONDS }
  );

  // Never log the URL (design rule 8).
  console.log(JSON.stringify({ msg: "upload-url issued", fileId }));

  return json(200, {
    fileId,
    uploadUrl,
    expiresInSeconds: UPLOAD_URL_TTL_SECONDS,
    requiredHeaders: { "Content-Type": contentType },
  });
};