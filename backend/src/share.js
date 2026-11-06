// share.js – POST /files/{id}/share
// Body: { recipientEmail, permission, expiresInHours? }
const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");
const { writeAudit } = require("./audit");

const ses = new SESClient({ region: process.env.AWS_SES_REGION || "ap-southeast-2" });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const FILES_TABLE    = process.env.FILES_TABLE;
const SHARES_TABLE   = process.env.SHARES_TABLE;
const AUDIT_TABLE    = process.env.AUDIT_TABLE;
const SENDER_EMAIL   = process.env.SES_SENDER_EMAIL;

const UUID_RE  = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  // Validate path param.
  const fileId = event.pathParameters?.id;
  if (!fileId || !UUID_RE.test(fileId)) {
    return json(400, { error: "Invalid file id" });
  }

  // Parse and validate body.
  let body;
  try { body = JSON.parse(event.body ?? "{}"); }
  catch { return json(400, { error: "Body must be valid JSON" }); }

  const recipientEmail = typeof body.recipientEmail === "string"
    ? body.recipientEmail.trim().toLowerCase()
    : null;

  if (!recipientEmail || !EMAIL_RE.test(recipientEmail) || recipientEmail.length > 254) {
    return json(400, { error: "recipientEmail must be a valid email address (max 254 chars)" });
  }
  if (recipientEmail === caller.email) {
    return json(400, { error: "Cannot share a file with yourself" });
  }

  const permission = body.permission;
  if (permission !== "view" && permission !== "download") {
    return json(400, { error: "permission must be \"view\" or \"download\"" });
  }

  let expiresAt; // epoch seconds for DynamoDB TTL, or undefined
  if (body.expiresInHours !== undefined) {
    const hours = body.expiresInHours;
    if (!Number.isInteger(hours) || hours < 1 || hours > 720) {
      return json(400, { error: "expiresInHours must be an integer from 1 to 720" });
    }
    expiresAt = Math.floor(Date.now() / 1000) + hours * 3600;
  }

  // Verify the file exists and the caller owns it.
  const { Item: file } = await ddb.send(
    new GetCommand({ TableName: FILES_TABLE, Key: { fileId }, ConsistentRead: true })
  );

  if (!file || !file.ownerEmail) {
    // Not found or corrupt record — CloudWatch only, never audit table.
    console.log(JSON.stringify({ msg: "share: file not found", fileId }));
    return json(404, { error: "Not found" });
  }

  if (file.ownerEmail !== caller.email) {
    // Not the owner — same 404 to avoid enumeration; audit denied.
    await writeAudit(ddb, AUDIT_TABLE, fileId, caller, "share", "denied",
      { targetEmail: recipientEmail });
    return json(404, { error: "Not found" });
  }

  // Write or overwrite the Shares record.
  const shareItem = {
    fileId,
    recipientEmail,
    permission,
    sharedBy: caller.email,
    sharedAt: Date.now(), // ms
  };
  if (expiresAt !== undefined) shareItem.expiresAt = expiresAt;

  await ddb.send(new PutCommand({ TableName: SHARES_TABLE, Item: shareItem }));

  await writeAudit(ddb, AUDIT_TABLE, fileId, caller, "share", "success",
    { targetEmail: recipientEmail });

  // Send SES notification — fire-and-forget; share succeeds even if email fails.
  if (SENDER_EMAIL) {
    const expiry = expiresAt
      ? `Expires: ${new Date(expiresAt * 1000).toUTCString()}`
      : "No expiry";
    try {
      await ses.send(new SendEmailCommand({
        Source: SENDER_EMAIL,
        Destination: { ToAddresses: [recipientEmail] },
        Message: {
          Subject: { Data: `CloudVault: ${caller.email} shared a file with you` },
          Body: {
            Text: {
              Data: [
                `${caller.email} has shared a file with you on CloudVault.`,
                ``,
                `File:       ${file.fileName}`,
                `Permission: ${permission}`,
                expiry,
                ``,
                `Log in to CloudVault to access the shared file.`,
                ``,
                `(View-only access cannot prevent screenshots or copying.)`,
              ].join("\n"),
            },
          },
        },
      }));
      console.log(JSON.stringify({ msg: "share notification sent", fileId }));
    } catch (sesErr) {
      // Log failure to CloudWatch; do NOT include email content or addresses in full.
      console.error(JSON.stringify({ msg: "ses_send_failed", fileId, error: String(sesErr) }));
    }
  }

  console.log(JSON.stringify({ msg: "share created", fileId, recipientEmail, permission }));
  return json(200, { fileId, recipientEmail, permission });
};

