import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Register through package.json's magpie.hooks. Set gatewayTimeoutMs to 3000
// in the plugin options so the short dispatchers can finish within 1500 ms.
// Missing sessions are skipped; a missing cwd stays empty and is never a key.
// Native hooks and this gateway observer can both notify: enable one route.
const scripts = fileURLToPath(
  new URL("../../plugins/cc-notify-hooks/scripts/", import.meta.url),
);
const dispatcherTimeoutMs = 1500;
const pendingKinds = ["gateway_response", "gateway_error"];

function identity(ctx) {
  if (ctx?.kind === "subagent" || ctx?.signal?.aborted) return null;
  if (typeof ctx?.session !== "string" || !ctx.session.trim()) return null;
  return {
    session_id: ctx.session,
    cwd: typeof ctx.cwd === "string" ? ctx.cwd : "",
    source: "magpie",
    client_agent: typeof ctx.agent === "string" ? ctx.agent : "",
    model: typeof ctx.model === "string" ? ctx.model : "",
  };
}

function optionPath(value, fallback) {
  if (typeof value !== "string" || !value.trim()) return fallback;
  if (value === "~") return homedir();
  return value.startsWith("~/") ? join(homedir(), value.slice(2)) : value;
}

function runScript(script, args, payload, ctx) {
  return new Promise((resolve) => {
    if (ctx.signal?.aborted) return resolve();

    let child;
    let timer;
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      ctx.signal?.removeEventListener("abort", stop);
      resolve();
    };
    const stop = () => {
      // End only the short dispatcher. Its already-queued notification workers
      // belong to the shared runtime and must survive this hook returning.
      try {
        child?.kill("SIGKILL");
      } catch {
        // A dispatcher may already have exited.
      }
      finish();
    };

    try {
      const configRoot = join(homedir(), ".config", "cc-notify-hooks");
      child = spawn("bash", [join(scripts, script), ...args], {
        detached: true,
        windowsHide: true,
        stdio: ["pipe", "ignore", "ignore"],
        env: {
          ...process.env,
          CC_NOTIFY_AGENT: "magpie",
          CC_NOTIFY_CONFIG: optionPath(
            ctx.options?.configPath,
            join(configRoot, "notify.json"),
          ),
          CC_NOTIFY_STATE_DIR: optionPath(
            ctx.options?.stateDir,
            join(configRoot, "state", "magpie"),
          ),
        },
      });
      child.once("error", finish);
      child.once("exit", finish);
      child.stdin.on("error", stop);
      child.unref();
      timer = setTimeout(stop, dispatcherTimeoutMs);
      ctx.signal?.addEventListener("abort", stop, { once: true });
      if (ctx.signal?.aborted) return stop();
      child.stdin.end(`${JSON.stringify(payload)}\n`);
    } catch {
      stop();
    }
  });
}

function textBlocks(blocks, textType, ignoredTypes = []) {
  if (!Array.isArray(blocks)) return null;
  const text = [];
  for (const block of blocks) {
    if (block?.type === textType && typeof block.text === "string") {
      text.push(block.text);
    } else if (!ignoredTypes.includes(block?.type)) {
      // Unknown blocks, tool calls and tool outputs are not final text.
      return null;
    }
  }
  return text.join("\n");
}

// Magpie consolidates streams into the client's ordinary response shape.
// Require an explicit complete finish and visible text; never summarize
// reasoning, tool output, truncated replies or unrecognized response formats.
function finalText(reply, protocol) {
  if (!reply || typeof reply !== "object" || reply.error != null) return "";

  switch (protocol) {
    case "chat": {
      if (!Array.isArray(reply.choices) || !reply.choices.length) return "";
      const texts = [];
      for (const choice of reply.choices) {
        const message = choice?.message;
        if (choice?.finish_reason !== "stop" || message?.role !== "assistant") {
          return "";
        }
        if (message.function_call != null) return "";
        if (
          message.tool_calls != null &&
          (!Array.isArray(message.tool_calls) || message.tool_calls.length)
        ) {
          return "";
        }
        const text =
          typeof message.content === "string"
            ? message.content
            : textBlocks(message.content, "text");
        if (!text?.trim()) return "";
        texts.push(text);
      }
      return texts[0];
    }
    case "responses": {
      if (reply.status !== "completed" || !Array.isArray(reply.output)) return "";
      const texts = [];
      for (const item of reply.output) {
        if (item?.status != null && item.status !== "completed") return "";
        if (item?.type === "reasoning") continue;
        // Only messages and reasoning are accepted. This also excludes
        // function_call, custom_tool_call, *_call_output and built-in tools.
        if (item?.type !== "message" || item.role !== "assistant") return "";
        const text = textBlocks(item.content, "output_text");
        if (text === null) return "";
        if (item.phase === "commentary") continue;
        if (item.phase != null && item.phase !== "final_answer") return "";
        if (text.trim()) texts.push(text);
      }
      return texts.join("\n");
    }
    case "anthropic": {
      if (
        reply.type !== "message" ||
        reply.role !== "assistant" ||
        !["end_turn", "stop_sequence"].includes(reply.stop_reason)
      ) {
        return "";
      }
      return (
        textBlocks(reply.content, "text", ["thinking", "redacted_thinking"]) ?? ""
      );
    }
    case "gemini": {
      if (!Array.isArray(reply.candidates) || !reply.candidates.length) return "";
      const texts = [];
      for (const candidate of reply.candidates) {
        if (
          candidate?.finishReason !== "STOP" ||
          candidate.content?.role !== "model" ||
          !Array.isArray(candidate.content.parts)
        ) {
          return "";
        }
        const parts = [];
        for (const part of candidate.content.parts) {
          if (
            !part ||
            part.functionCall != null ||
            part.functionResponse != null ||
            part.executableCode != null ||
            part.codeExecutionResult != null ||
            typeof part.text !== "string"
          ) {
            return "";
          }
          if (part.thought !== true) parts.push(part.text);
        }
        const text = parts.join("\n");
        if (!text.trim()) return "";
        texts.push(text);
      }
      return texts[0];
    }
    default:
      return "";
  }
}

export async function onRequest(_body, ctx) {
  try {
    const scope = identity(ctx);
    if (!scope) return;
    await Promise.all(
      pendingKinds.map((kind) =>
        runScript(
          "clear_pending.sh",
          [kind],
          { ...scope, hook_event_name: "GatewayRequest" },
          ctx,
        ),
      ),
    );
  } catch {
    // Notifications must never reject or rewrite a gateway request.
  }
  // undefined preserves the original request, including all tool declarations.
}

export async function onResponse(reply, ctx) {
  try {
    const scope = identity(ctx);
    if (!scope || (ctx.success !== true && ctx.success !== false)) return;

    let kind;
    let message;
    if (
      ctx.success === false ||
      reply?.error != null ||
      ["failed", "incomplete"].includes(reply?.status)
    ) {
      kind = "gateway_error";
      message = "模型请求失败或响应未完整接收";
    } else {
      const text = finalText(reply, ctx.protocol).trim();
      if (!text) return;
      kind = "gateway_response";
      const excerpt = text.slice(0, 600).replace(/\s+/g, " ").trim();
      const summary =
        excerpt.length > 240 ? `${excerpt.slice(0, 239)}…` : excerpt;
      message = `模型响应完成：${summary}`;
    }

    await runScript(
      "notify.sh",
      ["notification", kind],
      {
        ...scope,
        hook_event_name: "Notification",
        notification_type: kind,
        message,
      },
      ctx,
    );
  } catch {
    // Notification failures must not affect the response or gateway.
  }
}
