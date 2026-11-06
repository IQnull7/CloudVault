const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient, QueryCommand } = require("@aws-sdk/lib-dynamodb");
const { getCaller, json } = require("./auth");

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const FILES_TABLE = process.env.FILES_TABLE;

exports.handler = async (event) => {
  const caller = getCaller(event);
  if (!caller) return json(401, { error: "Unauthorized" });

  const result = await ddb.send(
    new QueryCommand({
      TableName: FILES_TABLE,
      IndexName: "owner-index",
      KeyConditionExpression: "ownerEmail = :me",
      ExpressionAttributeValues: { ":me": caller.email },
      ScanIndexForward: false, // newest first (sort key is createdAt)
      Limit: 100,
    })
  );

  const files = (result.Items ?? []).map((f) => ({
    fileId: f.fileId,
    fileName: f.fileName,
    sizeBytes: f.sizeBytes,
    contentType: f.contentType,
    createdAt: f.createdAt,
  }));

  return json(200, { files });
};
