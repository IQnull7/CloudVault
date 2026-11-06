// revokeShare.js – DELETE /files/{id}/share?recipientEmail=
// Owner only. Removes the Shares record and writes an audit event.
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, DeleteCommand } = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");
const { writeAudit } = require("./audit");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const FILES_TABLE  = process.env.FILES_TABLE;
const SHARES_TABLE = process.env.SHARES_TABLE;
const AUDIT_TABLE  = process.env.AUDIT_TABLE;

const UUID_RE  = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  const fileId = event.pathParameters?.id;
  if (!fileId || !UUID_RE.test(fileId)) {
    return json(400, { error: "Invalid file id" });
  }

  const rawEmail = event.queryStringParameters?.recipientEmail ?? "";
  const recipientEmail = rawEmail.trim().toLowerCase();
  if (!recipientEmail || !EMAIL_RE.test(recipientEmail) || recipientEmail.length > 254) {
    return json(400, { error: "recipientEmail query param must be a valid email address" });
  }

  // Verify file exists and caller owns it.
  const { Item: file } = await ddb.send(
    new GetCommand({ TableName: FILES_TABLE, Key: { fileId }, ConsistentRead: true })
  );

  if (!file || !file.ownerEmail || file.ownerEmail !== caller.email) {
    // Not found or not owner — CloudWatch only, same 404 to avoid enumeration.
    console.log(JSON.stringify({ msg: "revoke: not found or not owner", fileId }));
    return json(404, { error: "Not found" });
  }

  // Delete the share (idempotent — succeeds even if share doesn't exist).
  await ddb.send(
    new DeleteCommand({ TableName: SHARES_TABLE, Key: { fileId, recipientEmail } })
  );

  await writeAudit(ddb, AUDIT_TABLE, fileId, caller, "share", "success",
    { targetEmail: recipientEmail, detail: "revoke" });

  console.log(JSON.stringify({ msg: "share revoked", fileId, recipientEmail }));
  return json(200, { fileId, recipientEmail, revoked: true });
};

