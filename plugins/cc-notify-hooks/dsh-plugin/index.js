import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const name = "dsh-notify-hooks";
export const inject = ["workingDirectory"];

const bundledScripts = fileURLToPath(new URL("../scripts/", import.meta.url));

export function apply(ctx, config = {}) {
  const scripts = resolve(config.scriptsDir || bundledScripts);
  const dataDirectory = join(process.env.DSH_HOME || join(homedir(), ".dsh"), "cc-notify-hooks");
  const environment = {
    ...process.env,
    CC_NOTIFY_AGENT: "dsh",
    DSH_CC_NOTIFY: "1",
    CC_NOTIFY_CONFIG: resolve(config.configFile || config.configPath || process.env.CC_NOTIFY_CONFIG || join(dataDirectory, "notify.json")),
    CC_NOTIFY_STATE_DIR: resolve(config.stateDir || join(dataDirectory, "state")),
  };
  const queues = new Map();
  const sessions = new Map();
  const approvals = new Map();
  const lastAssistantText = new Map();
  let disposed = false;

  function payload(session, fields = {}) {
    if (!session?.header?.id || session.header.origin === "subagent") return null;
    return {
      session_id: session.header.id,
      cwd: ctx.workingDirectory.get(session) || session.header.cwd || "",
      ...fields,
    };
  }

  function execute(script, args, data) {
    return new Promise((done) => {
      const child = spawn("bash", [join(scripts, script), ...args], {
        env: environment,
        stdio: ["pipe", "ignore", "ignore"],
      });
      const timer = setTimeout(() => {
        child.kill();
        done();
      }, 3000);
      const finish = () => {
        clearTimeout(timer);
        done();
      };
      child.once("error", finish);
      child.once("close", finish);
      child.stdin.on("error", () => {});
      child.stdin.end(JSON.stringify(data));
    });
  }

  // Events are synchronous observers; serialize only local state writes per session.
  function enqueue(session, script, args = [], fields = {}) {
    if (disposed) return Promise.resolve();
    const data = payload(session, fields);
    if (!data) return Promise.resolve();
    const id = data.session_id;
    sessions.set(id, session);
    const task = (queues.get(id) || Promise.resolve())
      .then(() => execute(script, args, data))
      .catch(() => {}); // Notification failures cannot decide or block an agent action.
    queues.set(id, task);
    void task.then(() => {
      if (queues.get(id) === task) queues.delete(id);
    });
    return task;
  }

  function clear(session, kind, callId) {
    return enqueue(session, "clear_pending.sh", kind ? [kind, ...(callId ? [callId] : [])] : []);
  }

  ctx.on("session/event", (session, event) => {
    if (!session?.header?.id || session.header.origin === "subagent") return;
    const id = session.header.id;
    const data = event.data;
    if (event.type === "assistant/message") {
      const text = (data.message?.content || [])
        .filter((block) => block.type === "text" && typeof block.text === "string")
        .map((block) => block.text).join("");
      if (text) lastAssistantText.set(id, text);
    } else if (event.type === "turn/start") {
      lastAssistantText.delete(id);
      void clear(session);
    } else if (event.type === "approval/asked") {
      const pending = approvals.get(id) || new Set();
      pending.add(data.id);
      approvals.set(id, pending);
      void enqueue(session, "notify.sh", ["notification", "permission"], {
        hook_event_name: "PermissionRequest",
        tool_use_id: data.id,
        tool_name: data.toolName,
        message: data.reason || "dsh 正在等待授权",
      });
    } else if (event.type === "approval/decided") {
      approvals.get(id)?.delete(data.id);
      if (approvals.get(id)?.size === 0) approvals.delete(id);
      void clear(session, "permission", data.id);
    } else if (event.type === "turn/end") {
      const reason = data.reason.kind;
      approvals.delete(id);
      if (reason === "completed") {
        void enqueue(session, "notify.sh", ["stop"], {
          hook_event_name: "Stop",
          turn_id: String(data.turn),
          last_assistant_message: lastAssistantText.get(id) || "",
        });
      } else if (reason === "error" || reason === "max-tokens" || reason === "blocked") {
        void enqueue(session, "notify.sh", ["notification", "error"], {
          hook_event_name: "StopFailure",
          turn_id: String(data.turn),
          message: data.reason.error?.message ||
            (reason === "max-tokens" ? "dsh 回合达到输出 token 上限" : "dsh 回合未正常完成"),
        });
      } else {
        void clear(session);
      }
      lastAssistantText.delete(id);
    }
  });

  ctx.on("user-questions/request", async (request, next) => {
    const session = request.agent?.session;
    // An approval can also be rendered as a question card; its audit events own that notification.
    const approvalCard = request.questions?.every((question) => question.intent?.kind === "approval");
    if (!session?.header?.id || session.header.origin === "subagent" ||
        !request.questions?.length || request.signal?.aborted ||
        (approvalCard && approvals.get(session.header.id)?.size > 0)) {
      return next();
    }
    const callId = request.wait?.callId || randomUUID();
    void enqueue(session, "notify.sh", ["notification", "user_input"], {
      hook_event_name: "UserQuestion",
      tool_use_id: callId,
      tool_name: "ask_user_question",
      tool_input: { questions: request.questions },
    });
    try {
      return await next();
    } finally {
      void clear(session, "user_input", callId);
    }
  }, { prepend: true });

  ctx.on("agent/inbox/inserted", ({ agent }) => {
    void clear(agent.session);
  });
  ctx.on("agent/disposed", ({ agent }) => {
    const session = agent.session;
    void clear(session).then(() => sessions.delete(session.header.id));
    approvals.delete(session.header.id);
    lastAssistantText.delete(session.header.id);
  });

  ctx.effect(() => async () => {
    const pending = [...sessions.values()].map((session) => clear(session));
    disposed = true;
    await Promise.allSettled(pending);
    sessions.clear();
    approvals.clear();
    lastAssistantText.clear();
  }, "dsh-notify-hooks: cancel pending notifications");
}
