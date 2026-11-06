import React, { useState, useEffect } from "react";
import { signIn, signUp, confirmSignUp, signOut, getCurrentEmail } from "./auth";
import {
  listMyFiles,
  listSharedFiles,
  getUploadUrl,
  uploadToS3,
  completeUpload,
  getAccessUrl,
  shareFile,
  revokeShare,
  getAuditLog,
} from "./api";
import "./App.css";

export default function App() {
  const [currentUser, setCurrentUser] = useState(null);
  const [activeTab, setActiveTab] = useState("my-files"); // "my-files" | "shared"
  const [statusMsg, setStatusMsg] = useState("");
  const [errorMsg, setErrorMsg] = useState("");

  // Auth form state
  const [authMode, setAuthMode] = useState("login"); // "login" | "register" | "confirm"
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmCode, setConfirmCode] = useState("");

  // Data state
  const [myFiles, setMyFiles] = useState([]);
  const [sharedFiles, setSharedFiles] = useState([]);
  const [uploading, setUploading] = useState(false);

  // Modals state
  const [shareModal, setShareModal] = useState(null); // fileId or null
  const [shareEmail, setShareEmail] = useState("");
  const [sharePermission, setSharePermission] = useState("view");
  const [shareExpiryHours, setShareExpiryHours] = useState("");
  const [auditModal, setAuditModal] = useState(null); // { fileId, fileName, events } or null

  // Check login on mount
  useEffect(() => {
    getCurrentEmail().then((em) => {
      if (em) {
        setCurrentUser(em);
        loadFiles();
      }
    });
  }, []);

  const notify = (msg, isErr = false) => {
    if (isErr) setErrorMsg(msg);
    else setStatusMsg(msg);
    setTimeout(() => { setErrorMsg(""); setStatusMsg(""); }, 5000);
  };

  const loadFiles = async () => {
    try {
      const [mine, shared] = await Promise.all([listMyFiles(), listSharedFiles()]);
      setMyFiles(mine.files || []);
      setSharedFiles(shared.files || []);
    } catch (err) {
      notify(err.message, true);
    }
  };

  // Auth handlers
  const handleLogin = async (e) => {
    e.preventDefault();
    const res = await signIn(email, password);
    if (res.success) {
      const em = await getCurrentEmail();
      setCurrentUser(em);
      notify(`Logged in as ${em}`);
      loadFiles();
    } else {
      notify(res.error, true);
    }
  };

  const handleRegister = async (e) => {
    e.preventDefault();
    const res = await signUp(email, password);
    if (res.success) {
      setAuthMode("confirm");
      notify("Verification code sent to your email. Enter it below.");
    } else {
      notify(res.error, true);
    }
  };

  const handleConfirm = async (e) => {
    e.preventDefault();
    const res = await confirmSignUp(email, confirmCode);
    if (res.success) {
      setAuthMode("login");
      notify("Email confirmed! You can now log in.");
    } else {
      notify(res.error, true);
    }
  };

  const handleLogout = () => {
    signOut();
    setCurrentUser(null);
    setMyFiles([]);
    setSharedFiles([]);
  };

  // Upload handler: presigned PUT -> complete
  const handleUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.size > 10 * 1024 * 1024) {
      notify("File exceeds 10 MB limit.", true);
      return;
    }

    setUploading(true);
    try {
      notify("Requesting secure upload URL...");
      const { fileId, uploadUrl } = await getUploadUrl(file.name, file.size, file.type || "application/octet-stream");

      notify("Uploading directly to private S3 bucket...");
      await uploadToS3(uploadUrl, file);

      notify("Finalizing upload with backend...");
      await completeUpload(fileId);

      notify(`Upload complete: ${file.name}`);
      loadFiles();
    } catch (err) {
      notify(err.message, true);
    } finally {
      setUploading(false);
      e.target.value = "";
    }
  };

  // Access handler (presigned GET)
  const handleAccess = async (fileId, permission = "download") => {
    try {
      notify("Generating short-lived secure access link...");
      const { url } = await getAccessUrl(fileId);
      // Open inline or download
      if (permission === "view") {
        window.open(url, "_blank", "noopener,noreferrer");
      } else {
        const a = document.createElement("a");
        a.href = url;
        a.download = "";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
      }
    } catch (err) {
      notify(err.message, true);
    }
  };

  // Share handler
  const handleShareSubmit = async (e) => {
    e.preventDefault();
    try {
      const hours = shareExpiryHours ? parseInt(shareExpiryHours, 10) : undefined;
      await shareFile(shareModal, shareEmail, sharePermission, hours);
      notify(`File shared with ${shareEmail} (${sharePermission})`);
      setShareModal(null);
      setShareEmail("");
      setShareExpiryHours("");
    } catch (err) {
      notify(err.message, true);
    }
  };

  // Revoke handler
  const handleRevoke = async (fileId, recipientEmail) => {
    if (!confirm(`Revoke access for ${recipientEmail}?`)) return;
    try {
      await revokeShare(fileId, recipientEmail);
      notify(`Share revoked for ${recipientEmail}`);
      loadFiles();
    } catch (err) {
      notify(err.message, true);
    }
  };

  // Audit view handler
  const handleViewAudit = async (fileId, fileName) => {
    try {
      const data = await getAuditLog(fileId);
      setAuditModal({ fileId, fileName, events: data.events || [] });
    } catch (err) {
      notify(err.message, true);
    }
  };

  // ---------------- Render: Auth Screen ----------------
  if (!currentUser) {
    return (
      <div className="auth-container">
        <div className="auth-card">
          <div className="brand">
            <span className="logo-icon">🔒</span>
            <h1>CloudVault</h1>
          </div>
          <p className="subtitle">Security-first serverless cloud storage</p>

          {statusMsg && <div className="alert success">{statusMsg}</div>}
          {errorMsg && <div className="alert error">{errorMsg}</div>}

          {authMode === "login" && (
            <form onSubmit={handleLogin}>
              <label>Email address</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="user@example.com"
              />
              <label>Password</label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••••••"
              />
              <button type="submit" className="btn primary">Sign In</button>
              <p className="switch-mode">
                No account? <a href="#" onClick={() => setAuthMode("register")}>Register</a>
              </p>
            </form>
          )}

          {authMode === "register" && (
            <form onSubmit={handleRegister}>
              <label>Email address</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="user@example.com"
              />
              <label>Password (min 12 chars, upper, lower, num, symbol)</label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••••••"
              />
              <button type="submit" className="btn primary">Register</button>
              <p className="switch-mode">
                Already registered? <a href="#" onClick={() => setAuthMode("login")}>Sign in</a> |{" "}
                <a href="#" onClick={() => setAuthMode("confirm")}>Confirm code</a>
              </p>
            </form>
          )}

          {authMode === "confirm" && (
            <form onSubmit={handleConfirm}>
              <label>Email</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
              <label>Verification Code from Email</label>
              <input
                type="text"
                required
                value={confirmCode}
                onChange={(e) => setConfirmCode(e.target.value)}
                placeholder="123456"
              />
              <button type="submit" className="btn primary">Confirm Account</button>
              <p className="switch-mode">
                <a href="#" onClick={() => setAuthMode("login")}>Back to login</a>
              </p>
            </form>
          )}
        </div>
      </div>
    );
  }

  // ---------------- Render: Main App Screen ----------------
  return (
    <div className="app-container">
      {/* Top Navigation */}
      <header className="header">
        <div className="brand">
          <span className="logo-icon">🔒</span>
          <h2>CloudVault</h2>
        </div>
        <div className="user-info">
          <span className="email-badge">{currentUser}</span>
          <button className="btn outline sm" onClick={handleLogout}>Sign Out</button>
        </div>
      </header>

      {/* Notifications */}
      {statusMsg && <div className="alert-bar success">{statusMsg}</div>}
      {errorMsg && <div className="alert-bar error">{errorMsg}</div>}

      {/* Subheader & Actions */}
      <div className="action-bar">
        <div className="tabs">
          <button
            className={`tab ${activeTab === "my-files" ? "active" : ""}`}
            onClick={() => setActiveTab("my-files")}
          >
            My Files ({myFiles.length})
          </button>
          <button
            className={`tab ${activeTab === "shared" ? "active" : ""}`}
            onClick={() => setActiveTab("shared")}
          >
            Shared With Me ({sharedFiles.length})
          </button>
        </div>

        <div className="upload-btn-wrapper">
          <label className={`btn primary ${uploading ? "disabled" : ""}`}>
            {uploading ? "Uploading..." : "↑ Upload File"}
            <input
              type="file"
              disabled={uploading}
              onChange={handleUpload}
              style={{ display: "none" }}
            />
          </label>
        </div>
      </div>

      {/* Content Area */}
      <main className="content">
        {activeTab === "my-files" ? (
          <div className="table-card">
            {myFiles.length === 0 ? (
              <p className="empty-state">No files uploaded yet. Click <strong>Upload File</strong> above.</p>
            ) : (
              <table className="data-table">
                <thead>
                  <tr>
                    <th>File Name</th>
                    <th>Size</th>
                    <th>Uploaded</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {myFiles.map((f) => (
                    <tr key={f.fileId}>
                      <td className="bold">{f.fileName}</td>
                      <td>{(f.sizeBytes / 1024).toFixed(1)} KB</td>
                      <td>{new Date(f.createdAt).toLocaleDateString()}</td>
                      <td className="actions">
                        <button
                          className="btn sm"
                          onClick={() => handleAccess(f.fileId, "download")}
                        >
                          Download
                        </button>
                        <button
                          className="btn sm secondary"
                          onClick={() => setShareModal(f.fileId)}
                        >
                          Share
                        </button>
                        <button
                          className="btn sm outline"
                          onClick={() => handleViewAudit(f.fileId, f.fileName)}
                        >
                          Audit Log
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        ) : (
          <div className="table-card">
            {sharedFiles.length === 0 ? (
              <p className="empty-state">No files shared with you yet.</p>
            ) : (
              <table className="data-table">
                <thead>
                  <tr>
                    <th>File Name</th>
                    <th>Shared By</th>
                    <th>Permission</th>
                    <th>Expires</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {sharedFiles.map((f) => (
                    <tr key={f.fileId}>
                      <td className="bold">{f.fileName}</td>
                      <td>{f.sharedBy}</td>
                      <td>
                        <span className={`pill ${f.permission}`}>
                          {f.permission.toUpperCase()}
                        </span>
                      </td>
                      <td>
                        {f.expiresAt
                          ? new Date(f.expiresAt * 1000).toLocaleString()
                          : "Never"}
                      </td>
                      <td className="actions">
                        <button
                          className="btn sm"
                          onClick={() => handleAccess(f.fileId, f.permission)}
                        >
                          {f.permission === "view" ? "View (Inline)" : "Download"}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}
      </main>

      {/* Share Modal */}
      {shareModal && (
        <div className="modal-backdrop">
          <div className="modal">
            <h3>Share File</h3>
            <form onSubmit={handleShareSubmit}>
              <label>Recipient Email (must be registered)</label>
              <input
                type="email"
                required
                value={shareEmail}
                onChange={(e) => setShareEmail(e.target.value)}
                placeholder="colleague@example.com"
              />

              <label>Permission</label>
              <select
                value={sharePermission}
                onChange={(e) => setSharePermission(e.target.value)}
              >
                <option value="view">View Only (Inline disposition)</option>
                <option value="download">Download (Attachment disposition)</option>
              </select>

              <label>Expiry (Optional, 1–720 hours)</label>
              <input
                type="number"
                min="1"
                max="720"
                value={shareExpiryHours}
                onChange={(e) => setShareExpiryHours(e.target.value)}
                placeholder="Leave blank for no expiry"
              />

              <div className="modal-actions">
                <button type="button" className="btn outline" onClick={() => setShareModal(null)}>
                  Cancel
                </button>
                <button type="submit" className="btn primary">
                  Confirm Share
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Audit Log Modal */}
      {auditModal && (
        <div className="modal-backdrop">
          <div className="modal wide">
            <h3>Audit Log: {auditModal.fileName}</h3>
            <p className="subtitle">Immutable DynamoDB audit trail (newest first)</p>
            <div className="table-scroll">
              <table className="data-table sm">
                <thead>
                  <tr>
                    <th>Timestamp</th>
                    <th>Actor</th>
                    <th>Event</th>
                    <th>Outcome</th>
                    <th>Source IP</th>
                    <th>Detail</th>
                  </tr>
                </thead>
                <tbody>
                  {auditModal.events.map((e) => (
                    <tr key={e.sk}>
                      <td>{new Date(e.ts).toLocaleString()}</td>
                      <td>{e.actorEmail}</td>
                      <td><span className="badge">{e.eventType}</span></td>
                      <td>
                        <span className={`pill-sm ${e.outcome}`}>
                          {e.outcome}
                        </span>
                      </td>
                      <td><code>{e.sourceIp}</code></td>
                      <td>{e.targetEmail ? `target: ${e.targetEmail}` : (e.detail || "-")}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="modal-actions">
              <button className="btn primary sm" onClick={() => setAuditModal(null)}>
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
