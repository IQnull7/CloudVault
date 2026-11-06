// access.js – GET /files/{id}/access
// Owner always gets download; shared users get what their permission says.
const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand } = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");
const { writeAudit } = require("./audit");

const s3  = new S3Client({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const BUCKET       = process.env.BUCKET_NAME;
const FILES_TABLE  = process.env.FILES_TABLE;
const SHARES_TABLE = process.env.SHARES_TABLE;
const AUDIT_TABLE  = process.env.AUDIT_TABLE;

const UUID_RE      = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const URL_EXPIRY_S = 60;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  const fileId = event.pathParameters?.id;
  if (!fileId || !UUID_RE.test(fileId)) {
    return json(400, { error: "Invalid file id" });
  }

  // Fetch file record.
  const { Item: file } = await ddb.send(
    new GetCommand({ TableName: FILES_TABLE, Key: { fileId }, ConsistentRead: true })
  );

  if (!file || !file.ownerEmail) {
    // File doesn't exist — CloudWatch only.
    console.log(JSON.stringify({ msg: "access: file not found", fileId }));
    return json(404, { error: "Not found" });
  }

  let permission;

  if (file.ownerEmail === caller.email) {
    // Owner always gets download access.
    permission = "download";
  } else {
    // Check Shares table.
    const { Item: share } = await ddb.send(
      new GetCommand({
        TableName: SHARES_TABLE,
        Key: { fileId, recipientEmail: caller.email },
        ConsistentRead: true,
      })
    );

    if (!share) {
      await writeAudit(ddb, AUDIT_TABLE, fileId, caller, "view", "denied");
      return json(403, { error: "Forbidden" });
    }

    // Explicit expiry check — TTL deletion is asynchronous.
    if (share.expiresAt && share.expiresAt < Math.floor(Date.now() / 1000)) {
      await writeAudit(ddb, AUDIT_TABLE, fileId, caller, "view", "denied",
        { detail: "share_expired" });
      return json(403, { error: "Forbidden" });
    }

    permission = share.permission; // "view" or "download"
  }

  // Build presigned GET URL.
  const disposition = permission === "view" ? "inline" : "attachment";
  const eventType   = permission === "view" ? "view"   : "download";

  const cmd = new GetObjectCommand({
    Bucket: BUCKET,
    Key: file.s3Key,
    ResponseContentDisposition: `${disposition}; filename="${file.fileName}"`,
  });

  const url = await getSignedUrl(s3, cmd, { expiresIn: URL_EXPIRY_S });

  await writeAudit(ddb, AUDIT_TABLE, fileId, caller, eventType, "success");

  // Never log the URL.
  console.log(JSON.stringify({ msg: "access url issued", fileId, eventType }));

  return json(200, { url, expiresInSeconds: URL_EXPIRY_S });
};

