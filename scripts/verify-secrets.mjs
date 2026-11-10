// Post-deploy check for the two Worker Secrets.
// The upstream installer writes generated tokens into this git-ignored file.
// See PATCH_NOTES.md for why this check exists.

import { existsSync, readFileSync } from "node:fs";

const SETUP_PATH = "config/agent-setup.local.json";
const ADMIN_KEY = "SUB_STORE_ADMIN_TOKEN";
const DOWNLOAD_KEY = "SUB_STORE_PUBLIC_DOWNLOAD_TOKEN";

if (!existsSync(SETUP_PATH)) {
  console.error(`ERROR: ${SETUP_PATH} not found. Run the installer first.`);
  process.exit(1);
}

let setup;
try {
  setup = JSON.parse(readFileSync(SETUP_PATH, "utf8"));
} catch (error) {
  console.error(`ERROR: cannot parse ${SETUP_PATH}: ${error.message}`);
  process.exit(1);
}

const deployment = setup.deployment || {};
const adminToken = String(deployment.adminToken || "").trim();
const downloadToken = String(deployment.downloadToken || "").trim();
const problems = [];

if (!adminToken) problems.push(`${ADMIN_KEY} is empty`);
if (!downloadToken) problems.push(`${DOWNLOAD_KEY} is empty`);
if (adminToken && downloadToken && adminToken === downloadToken) {
  problems.push("admin token and download token must be different");
}
for (const [name, value] of [
  [ADMIN_KEY, adminToken],
  [DOWNLOAD_KEY, downloadToken],
]) {
  if (value && value.length < 32) {
    problems.push(`${name} is shorter than 32 characters`);
  }
}

if (problems.length > 0) {
  for (const problem of problems) console.error(`ERROR: ${problem}`);
  console.error(`Fix ${SETUP_PATH} and rerun: pnpm run install:quick`);
  process.exit(1);
}

console.log(`OK: both Worker Secrets are configured in ${SETUP_PATH}.`);
console.log("");
console.log("Save the Admin URL and both tokens in a password manager.");
console.log(`Never commit ${SETUP_PATH}; it is covered by .gitignore.`);
