// Self-report extension for the pi coding agent, installed into
// ~/.pi/agent/extensions/ by ~/.config/rex/install-hooks.sh (pi
// autoloads that directory). Records which conversation belongs to this
// Rex block, so a restored terminal resumes the exact session that ran
// in it. pi prefers the session file path over the id for resuming.
//
// REX_AGENT_RESUME_HOOK_VERSION=1

import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export default function (pi: any) {
  pi.on("session_start", (_event: unknown, ctx: any) => {
    try {
      if (ctx.mode !== "tui") return;
      const block = process.env.REX_BLOCK;
      if (!block || process.env.REX_AGENT_RESUME === "0") return;

      const id = ctx.sessionManager.getSessionId();
      const file = ctx.sessionManager.getSessionFile();
      const ref = file || id;
      if (!ref) return;

      const cache = path.join(
        process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"),
        "rex-agent-resume",
      );
      fs.mkdirSync(cache, { recursive: true });
      const sessions = path.join(cache, "sessions.tsv");
      const lock = path.join(cache, ".sessions.lock");
      for (let i = 0; i < 20; i++) {
        try {
          fs.mkdirSync(lock);
          let lines: string[] = [];
          try {
            lines = fs
              .readFileSync(sessions, "utf8")
              .split("\n")
              .filter((l) => l && !l.startsWith(block + "\t"));
          } catch {
            lines = []; // first report: the file does not exist yet
          }
          lines.push(
            [block, "pi", ref, Math.floor(Date.now() / 1000)].join("\t"),
          );
          const tmp = sessions + ".tmp";
          fs.writeFileSync(tmp, lines.join("\n") + "\n");
          fs.renameSync(tmp, sessions);
          fs.rmdirSync(lock);
          return;
        } catch (e: any) {
          if (e && e.code === "EEXIST") {
            Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50);
            continue;
          }
          return; // never disturb the agent
        }
      }
    } catch {
      // never disturb the agent
    }
  });
}
