// Returns { email, sourceIp } for a valid ID-token caller, or null.
function getCaller(event) {
  const claims = event.requestContext?.authorizer?.jwt?.claims;
  if (!claims) return null;

  // Claims arrive as strings from API Gateway, so "true" not true.
  if (claims.token_use !== "id") return null;
  if (claims.email_verified !== "true") return null;
  if (!claims.email) return null;

  return {
    email: String(claims.email).toLowerCase(),
    sourceIp: event.requestContext?.http?.sourceIp ?? "unknown",
  };
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  };
}

module.exports = { getCaller, json };