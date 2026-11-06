// audit.js – shared writeAudit helper used by all Lambdas.
// Callers must pass the already-constructed ddb DocumentClient so each Lambda
// keeps its own SDK instance (no shared state across warm invocations).
const { randomUUID } = require("crypto");
const { PutCommand } = require("@aws-sdk/lib-dynamodb");

/**
 * Append one audit record. Never throws: failures are logged to CloudWatch only.
 *
 * @param {import("@aws-sdk/lib-dynamodb").DynamoDBDocumentClient} ddb
 * @param {string} auditTable  - value of AUDIT_TABLE env var
 * @param {string} fileId      - the file this event concerns
 * @param {{ email: string, sourceIp: string }} caller
 * @param {string} eventType   - "upload" | "download" | "share" | "view"
 * @param {string} outcome     - "success" | "denied" | "not_found"
 * @param {object} [extra]     - optional: { targetEmail, detail }
 */
async function writeAudit(ddb, auditTable, fileId, caller, eventType, outcome, extra = {}) {
  const ts = Date.now();
  const item = {
    fileId,
    sk: `${String(ts).padStart(13, "0")}#${randomUUID()}`,
    actorEmail: caller.email,
    eventType,
    outcome,
    sourceIp: caller.sourceIp,
    ts,
  };
  if (extra.targetEmail) item.targetEmail = extra.targetEmail;
  if (extra.detail)      item.detail      = extra.detail;

  try {
    await ddb.send(
      new PutCommand({
        TableName: auditTable,
        Item: item,
        ConditionExpression: "attribute_not_exists(fileId) AND attribute_not_exists(sk)",
      })
    );
  } catch (err) {
    // Audit failure must never break the main flow.
    console.error(JSON.stringify({ msg: "audit_write_failed", eventType, outcome, error: String(err) }));
  }
}

module.exports = { writeAudit };

