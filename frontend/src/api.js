// api.js – All API calls to the CloudVault backend.
// Every call attaches the ID token (not access token) as Bearer.
// Never logs the token or presigned URLs.
import { getIdToken } from "./auth";

const BASE = import.meta.env.VITE_API_ENDPOINT;

async function request(method, path, body) {
  const token = await getIdToken();
  const headers = { "Content-Type": "application/json" };
  if (token) headers["Authorization"] = `Bearer ${token}`;

  const opts = { method, headers };
  if (body !== undefined) opts.body = JSON.stringify(body);

  const res = await fetch(`${BASE}${path}`, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.error || "Request failed"), { status: res.status, data });
  return data;
}

// Files
export const getUploadUrl = (fileName, sizeBytes, contentType) =>
  request("POST", "/files/upload-url", { fileName, sizeBytes, contentType });

export const completeUpload = (fileId) =>
  request("POST", `/files/${fileId}/complete`);

export const listMyFiles = () => request("GET", "/files");

export const listSharedFiles = () => request("GET", "/files/shared");

// Access – returns { url, expiresInSeconds }. Never store or log url.
export const getAccessUrl = (fileId) => request("GET", `/files/${fileId}/access`);

// Sharing
export const shareFile = (fileId, recipientEmail, permission, expiresInHours) =>
  request("POST", `/files/${fileId}/share`, {
    recipientEmail,
    permission,
    ...(expiresInHours ? { expiresInHours } : {}),
  });

export const revokeShare = (fileId, recipientEmail) =>
  request("DELETE", `/files/${fileId}/share?recipientEmail=${encodeURIComponent(recipientEmail)}`);

// Audit
export const getAuditLog = (fileId) => request("GET", `/files/${fileId}/audit`);

// Direct S3 presigned PUT (browser → S3, no auth header needed)
export async function uploadToS3(presignedUrl, file) {
  const res = await fetch(presignedUrl, {
    method: "PUT",
    headers: { "Content-Type": file.type },
    body: file,
  });
  if (!res.ok) throw new Error(`S3 upload failed: ${res.status}`);
}

