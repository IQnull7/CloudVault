const { S3Client, HeadObjectCommand } = require("@aws-sdk/client-s3");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
} = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");
const { writeAudit } = require("./audit");

const s3 = new S3Client({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const BUCKET = process.env.BUCKET_NAME;
const FILES_TABLE = process.env.FILES_TABLE;
const AUDIT_TABLE = process.env.AUDIT_TABLE;
const MAX_BYTES = 10 * 1024 * 1024;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  const fileId = event.pathParameters?.id;
  if (!fileId || !UUID_RE.test(fileId)) {
    return json(400, { error: "Invalid file id" });
  }

  const { Item: item } = await ddb.send(
    new GetCommand({
      TableName: FILES_TABLE,
      Key: { fileId },
      ConsistentRead: true,
    })
  );

  // Already completed by the owner: friendly conflict.
  if (item && item.ownerEmail === caller.email) {
    return json(409, { error: "Upload already completed" });
  }

  // Missing, or someone else's pending upload: same 404 either way.
  // CloudWatch only; never the audit table for unproven file IDs.
  if (!item || item.status !== "pending" || item.pendingOwner !== caller.email) {
    console.log(JSON.stringify({ msg: "complete rejected", fileId, reason: "not_found_or_not_owner" }));
    return json(404, { error: "Not found" });
  }

  if (item.pendingExpiresAt < Date.now()) {
    return json(410, { error: "Upload window expired; request a new upload URL" });
  }

  // The server computes the key. The client never supplies it.
  const s3Key = `uploads/${fileId}`;

  let head;
  try {
    head = await s3.send(new HeadObjectCommand({ Bucket: BUCKET, Key: s3Key }));
  } catch (err) {
    // Without s3:ListBucket, S3 answers 403 instead of 404 for a missing key.
    const code = err.$metadata?.httpStatusCode;
    if (code === 404 || code === 403) {
      return json(400, { error: "No uploaded object found for this file id" });
    }
    throw err;
  }

  const realSize = head.ContentLength;
  const realType = head.ContentType;
  if (
    realSize > MAX_BYTES ||
    realSize !== item.declaredSize ||
    realType !== item.declaredType
  ) {
    console.log(JSON.stringify({ msg: "complete rejected", fileId, reason: "object_mismatch" }));
    return json(422, { error: "Uploaded object does not match what was declared" });
  }

  try {
    await ddb.send(
      new PutCommand({
        TableName: FILES_TABLE,
        Item: {
          fileId,
          ownerEmail: caller.email,
          fileName: item.fileName,
          s3Key,
          sizeBytes: realSize,
          contentType: realType,
          tags: [],
          createdAt: Date.now(),
        },
        // #s because "status" is a DynamoDB reserved word.
        ConditionExpression: "#s = :pending AND pendingOwner = :me",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: { ":pending": "pending", ":me": caller.email },
      })
    );
  } catch (err) {
    if (err.name === "ConditionalCheckFailedException") {
      return json(409, { error: "Upload already completed" });
    }
    throw err;
  }

  await writeAudit(ddb, AUDIT_TABLE, fileId, caller, "upload", "success");

  return json(200, { fileId, fileName: item.fileName, sizeBytes: realSize, contentType: realType });
};