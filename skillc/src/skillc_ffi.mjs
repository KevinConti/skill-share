import { Ok, Error } from "../prelude.mjs";
import { execSync } from "child_process";

export function halt(code) {
  process.exit(code);
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
