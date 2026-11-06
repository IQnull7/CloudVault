// auth.js – Cognito SRP authentication helpers using amazon-cognito-identity-js
import {
  CognitoUserPool,
  CognitoUser,
  AuthenticationDetails,
} from "amazon-cognito-identity-js";

const poolData = {
  UserPoolId: import.meta.env.VITE_USER_POOL_ID,
  ClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
};

const userPool = new CognitoUserPool(poolData);

/** Returns the current Cognito session's ID token string, or null. */
export function getIdToken() {
  return new Promise((resolve) => {
    const user = userPool.getCurrentUser();
    if (!user) return resolve(null);
    user.getSession((err, session) => {
      if (err || !session?.isValid()) return resolve(null);
      resolve(session.getIdToken().getJwtToken());
    });
  });
}

/** Returns the current CognitoUser email from the session payload, or null. */
export function getCurrentEmail() {
  return new Promise((resolve) => {
    const user = userPool.getCurrentUser();
    if (!user) return resolve(null);
    user.getSession((err, session) => {
      if (err || !session?.isValid()) return resolve(null);
      resolve(session.getIdToken().payload.email ?? null);
    });
  });
}

/** Sign in with SRP. Returns { success, requiresMfa, error }. */
export function signIn(email, password) {
  return new Promise((resolve) => {
    const authDetails = new AuthenticationDetails({
      Username: email.toLowerCase(),
      Password: password,
    });
    const cognitoUser = new CognitoUser({
      Username: email.toLowerCase(),
      Pool: userPool,
    });
    cognitoUser.authenticateUser(authDetails, {
      onSuccess: () => resolve({ success: true }),
      onFailure: (err) => resolve({ success: false, error: err.message }),
      totpRequired: () => resolve({ success: false, requiresMfa: true, cognitoUser }),
    });
  });
}

/** Confirm MFA TOTP code. */
export function confirmMfa(cognitoUser, code) {
  return new Promise((resolve) => {
    cognitoUser.sendMFACode(code, {
      onSuccess: () => resolve({ success: true }),
      onFailure: (err) => resolve({ success: false, error: err.message }),
    }, "SOFTWARE_TOKEN_MFA");
  });
}

/** Register a new user. */
export function signUp(email, password) {
  return new Promise((resolve) => {
    userPool.signUp(email.toLowerCase(), password, [], null, (err, result) => {
      if (err) return resolve({ success: false, error: err.message });
      resolve({ success: true, user: result.user });
    });
  });
}

/** Confirm registration with the emailed verification code. */
export function confirmSignUp(email, code) {
  return new Promise((resolve) => {
    const cognitoUser = new CognitoUser({
      Username: email.toLowerCase(),
      Pool: userPool,
    });
    cognitoUser.confirmRegistration(code, true, (err) => {
      if (err) return resolve({ success: false, error: err.message });
      resolve({ success: true });
    });
  });
}

/** Sign out the current user locally. */
export function signOut() {
  const user = userPool.getCurrentUser();
  if (user) user.signOut();
}

