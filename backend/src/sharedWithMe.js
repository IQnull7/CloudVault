// sharedWithMe.js – GET /files/shared
// Lists all non-expired shares where the caller is the recipient.
// Returns file metadata fetched via BatchGetItem; never returns s3Key.
const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const {
  DynamoDBDocumentClient,
  QueryCommand,
  BatchGetCommand,
} = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const FILES_TABLE  = process.env.FILES_TABLE;
const SHARES_TABLE = process.env.SHARES_TABLE;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  // Query recipient-index for all shares targeting this user.
  const result = await ddb.send(
    new QueryCommand({
      TableName: SHARES_TABLE,
      IndexName: "recipient-index",
      KeyConditionExpression: "recipientEmail = :me",
      ExpressionAttributeValues: { ":me": caller.email },
      Limit: 200,
    })
  );

  const nowSec = Math.floor(Date.now() / 1000);

  // Filter out expired shares (TTL deletion is asynchronous).
  const active = (result.Items ?? []).filter(
    (s) => !s.expiresAt || s.expiresAt >= nowSec
  );

  if (active.length === 0) {
    return json(200, { files: [] });
  }

  // BatchGetItem to fetch file metadata (max 100 per call; we limit Shares query to 200).
  // Split into batches of 100.
  const files = [];
  for (let i = 0; i < active.length; i += 100) {
    const batch = active.slice(i, i + 100);
    const keys  = batch.map((s) => ({ fileId: s.fileId }));

    const batchResult = await ddb.send(
      new BatchGetCommand({
        RequestItems: {
          [FILES_TABLE]: {
            Keys: keys,
            ProjectionExpression: "fileId, fileName, sizeBytes, contentType, createdAt",
          },
        },
      })
    );

    const fileMap = {};
    for (const f of (batchResult.Responses?.[FILES_TABLE] ?? [])) {
      fileMap[f.fileId] = f;
    }

    for (const share of batch) {
      const f = fileMap[share.fileId];
      if (!f) continue; // file was deleted, skip silently
      files.push({
        fileId:      f.fileId,
        fileName:    f.fileName,
        sizeBytes:   f.sizeBytes,
        contentType: f.contentType,
        createdAt:   f.createdAt,
        permission:  share.permission,
        sharedBy:    share.sharedBy,
        expiresAt:   share.expiresAt ?? null,
      });
    }
  }

  return json(200, { files });
};

