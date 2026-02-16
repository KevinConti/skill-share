import { Ok, Error } from "../prelude.mjs";
import { execSync } from "child_process";
import os from "os";

export function halt(code) {
  process.exit(code);
}

export function platform_string() {
  return process.platform;
}

export function tmpdir() {
  return os.tmpdir();
}

export function get_env(name) {
  const value = process.env[name];
  return value === undefined ? new Error(undefined) : new Ok(value);
}

export function exec(cmd) {
  try {
    const stdout = execSync(cmd, { encoding: "utf-8", timeout: 120000 });
    return new Ok(stdout.trim());
  } catch (err) {
    const msg = err.stderr ? err.stderr.trim() : err.message;
    return new Error(msg);
  }
}
