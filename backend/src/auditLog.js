// auditLog.js – GET /files/{id}/audit
// Owner only: returns the most recent 100 audit events for a file.
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, GetCommand, QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const FILES_TABLE = process.env.FILES_TABLE;
const AUDIT_TABLE = process.env.AUDIT_TABLE;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  const fileId = event.pathParameters?.id;
  if (!fileId || !UUID_RE.test(fileId)) {
    return json(400, { error: "Invalid file id" });
  }

  // Verify file exists and caller owns it.
  const { Item: file } = await ddb.send(
    new GetCommand({ TableName: FILES_TABLE, Key: { fileId }, ConsistentRead: true })
  );

  if (!file || !file.ownerEmail || file.ownerEmail !== caller.email) {
    // Not found or not owner — CloudWatch only, return 404.
    console.log(JSON.stringify({ msg: "audit: not found or not owner", fileId, caller: caller.email }));
    return json(404, { error: "Not found" });
  }

  // Query AuditLogs by fileId, newest first (ScanIndexForward: false on sk).
  const result = await ddb.send(
    new QueryCommand({
      TableName: AUDIT_TABLE,
      KeyConditionExpression: "fileId = :id",
      ExpressionAttributeValues: { ":id": fileId },
      ScanIndexForward: false,
      Limit: 100,
    })
  );

  const events = (result.Items ?? []).map((e) => ({
    sk:          e.sk,
    actorEmail:  e.actorEmail,
    eventType:   e.eventType,
    outcome:     e.outcome,
    sourceIp:    e.sourceIp,
    ts:          e.ts,
    ...(e.targetEmail ? { targetEmail: e.targetEmail } : {}),
    ...(e.detail      ? { detail:      e.detail      } : {}),
  }));

  return json(200, { fileId, events });
};

