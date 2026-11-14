/**
 * dsh-notify-hooks plugin unit test (no external dependencies).
 *
 * Installs stub bash scripts into a temp "scriptsDir", drives the plugin's
 * `apply()` with a mocked cordis ctx, and asserts that each harness
 * interception point spawns the right cc-notify-hooks script with the right
 * payload, environment, and (for waterfalls) always delegates via next().
 *
 * Run: node plugins/cc-notify-hooks/dsh-plugin/test/plugin.test.mjs
 */

import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'

const PLUGIN_URL = pathToFileURL(new URL('../index.js', import.meta.url).pathname).href
const { name, apply } = await import(PLUGIN_URL)

const results = []
function pass(label) {
  results.push({ ok: true })
  console.log(`PASS  ${label}`)
}
function fail(label, detail = '') {
  results.push({ ok: false })
  console.log(`FAIL  ${label}${detail ? `  (${detail})` : ''}`)
}

// ---- stub scripts that capture their invocation ---------------------------
const tmp = mkdtempSync(join(tmpdir(), 'dsh-notify-hooks-test-'))
const scriptsDir = join(tmp, 'scripts')
const captureDir = join(tmp, 'capture')
mkdirSync(scriptsDir)
mkdirSync(captureDir)

function stubScript(scriptName) {
  // Each stub records: argv, stdin payload, and the interesting env vars.
  const path = join(scriptsDir, scriptName)
  const logPath = join(captureDir, `${scriptName}.log`)
  writeFileSync(path, `#!/usr/bin/env bash
payload=$(cat)
{
  echo "argv=$*"
  echo "payload=$payload"
  echo "agent=$CC_NOTIFY_AGENT"
  echo "dshenv=$DSH_CC_NOTIFY"
  echo "state=$CC_NOTIFY_STATE_DIR"
  echo "config=$CC_NOTIFY_CONFIG"
} > "${logPath}"
`, { mode: 0o755 })
  return path
}
stubScript('notify.sh')
stubScript('clear_pending.sh')
stubScript('pre_tool_use.sh')

// ---- fake cordis ctx ------------------------------------------------------
const listeners = new Map()
const ctx = {
  logger: { info() {}, warn() {} },
  on(event, cb) {
    const list = listeners.get(event) ?? []
    list.push(cb)
    listeners.set(event, list)
  },
}
function fire(event, ...args) {
  for (const cb of listeners.get(event) ?? []) cb(...args)
}
/**
 * Drive a waterfall: the last argument is the value `next()` resolves to;
 * any middle arguments are forwarded between the payload and `next`.
 */
async function fireWaterfall(event, payload, ...rest) {
  const nextValue = rest.pop()
  const outs = []
  for (const cb of listeners.get(event) ?? []) {
    outs.push(await cb(payload, ...rest, async () => nextValue))
  }
  return outs
}

apply(ctx, { scriptsDir, stateDir: join(tmp, 'state') })

const capture = (script) => readFileSync(join(captureDir, `${script}.log`), 'utf8')
const payloadOf = (script) => {
  const m = capture(script).match(/^payload=(.*)$/m)
  return m ? JSON.parse(m[1]) : null
}
const envOf = (script) => {
  const text = capture(script)
  return {
    agent: text.match(/^agent=(.*)$/m)?.[1] ?? '',
    dshenv: text.match(/^dshenv=(.*)$/m)?.[1] ?? '',
    state: text.match(/^state=(.*)$/m)?.[1] ?? '',
    config: text.match(/^config=(.*)$/m)?.[1] ?? '',
  }
}
const waitTick = () => new Promise((resolve) => setTimeout(resolve, 100))

// ---- 1. approval/request → notify.sh notification + always delegates -------
{
  const req = {
    agent: { session: { header: { id: 'session-1', cwd: '/tmp/proj' } } },
    toolName: 'bash',
    callId: 'call-1',
    reason: 'run rm -rf /',
    signal: null,
  }
  const outcome = await fireWaterfall('approval/request', req, 'allowed-once')
  await waitTick()
  const payload = payloadOf('notify.sh')
  const env = envOf('notify.sh')
  const ok =
    outcome.length === 1 && outcome[0] === 'allowed-once' &&
    payload?.hook_event_name === 'Notification' &&
    payload?.notification_type === 'permission_prompt' &&
    payload?.message === 'run rm -rf /' &&
    payload?.tool_name === 'bash' &&
    payload?.session_id === 'session-1' &&
    payload?.cwd === '/tmp/proj' &&
    env.dshenv === '1' && env.state === join(tmp, 'state')
  ok
    ? pass('approval/request spawns notify.sh notification and delegates next()')
    : fail('approval/request', JSON.stringify({ payload, env, outcome }))
}

// ---- 2. agent/turn-stopping → notify.sh stop with tracked assistant text ---
{
  fire('session/event', { id: 'session-1' }, { type: 'assistant/message', data: { message: { content: [{ type: 'text', text: '任务完成。' }, { type: 'reasoning', text: 'ignored' }] } } })
  fire('agent/turn-stopping', { agent: { session: { header: { id: 'session-1', cwd: '/tmp/proj' } } }, turn: 3, signal: null })
  await waitTick()
  const payload = payloadOf('notify.sh')
  const ok =
    payload?.hook_event_name === 'Stop' &&
    payload?.last_assistant_message === '任务完成。' &&
    payload?.session_id === 'session-1' &&
    capture('notify.sh').includes('argv=stop')
  ok
    ? pass('agent/turn-stopping spawns notify.sh stop with tracked last_assistant_message')
    : fail('agent/turn-stopping', JSON.stringify(payload))
}

// ---- 3. agent/pre-step → clear_pending.sh + delegates ----------------------
{
  const outcome = await fireWaterfall('agent/pre-step', {
    agent: { session: { header: { id: 'session-1', cwd: '/tmp/proj' } } },
    messages: [{ content: [{ type: 'text', text: '继续' }] }],
    turn: 4, step: 1, signal: null,
  }, { kind: 'enter', messages: [] })
  await waitTick()
  const payload = payloadOf('clear_pending.sh')
  const ok =
    outcome.length === 1 && outcome[0]?.kind === 'enter' &&
    payload?.hook_event_name === 'UserPromptSubmit' &&
    payload?.prompt === '继续'
  ok
    ? pass('agent/pre-step spawns clear_pending.sh and delegates next()')
    : fail('agent/pre-step', JSON.stringify({ payload, outcome }))
}

// ---- 4. tools/pre-execute ask_user_question → pre_tool_use.sh --------------
{
  const exec = {
    name: 'ask_user_question',
    arguments: { questions: [{ header: '范围', question: '修复哪些？', options: [{ label: '全部' }] }] },
    callId: 'call-ask',
    agent: { session: { header: { id: 'session-1', cwd: '/tmp/proj' } } },
  }
  const outcome = await fireWaterfall('tools/pre-execute', exec, { kind: 'allow' })
  await waitTick()
  const payload = payloadOf('pre_tool_use.sh')
  const ok =
    outcome.length === 1 && outcome[0]?.kind === 'allow' &&
    payload?.hook_event_name === 'PreToolUse' &&
    payload?.tool_name === 'request_user_input' &&
    payload?.tool_input?.questions?.[0]?.header === '范围' &&
    payload?.tool_use_id === 'call-ask'
  ok
    ? pass('tools/pre-execute rewrites ask_user_question and delegates next()')
    : fail('tools/pre-execute', JSON.stringify(payload))
}

// ---- 5. tools/pre-execute ordinary tool keeps its name ---------------------
{
  const exec = {
    name: 'bash',
    arguments: { command: 'true' },
    callId: 'call-bash',
    agent: { session: { header: { id: 'session-1', cwd: '/tmp/proj' } } },
  }
  await fireWaterfall('tools/pre-execute', exec, { kind: 'allow' })
  await waitTick()
  const payload = payloadOf('pre_tool_use.sh')
  payload?.tool_name === 'bash'
    ? pass('tools/pre-execute keeps ordinary tool names')
    : fail('tools/pre-execute ordinary', JSON.stringify(payload))
}

// ---- 6. tools/post-execute ask_user_question → clear_pending.sh user_input --
{
  const exec = {
    name: 'ask_user_question',
    callId: 'call-ask',
    agent: { session: { header: { id: 'session-1', cwd: '/tmp/proj' } } },
  }
  const outcome = await fireWaterfall('tools/post-execute', exec, { kind: 'accept' }, { kind: 'accept' })
  await waitTick()
  const payload = payloadOf('clear_pending.sh')
  const ok =
    outcome.length === 1 && outcome[0]?.kind === 'accept' &&
    payload?.hook_event_name === 'PostToolUse' &&
    payload?.tool_name === 'request_user_input' &&
    capture('clear_pending.sh').includes('argv=user_input')
  ok
    ? pass('tools/post-execute clears user_input pending after question tool')
    : fail('tools/post-execute', JSON.stringify({ payload, outcome }))
}

// ---- 7. missing scriptsDir disables the plugin gracefully ------------------
{
  const warnCalls = []
  const disabled = {
    logger: { info() {}, warn(msg) { warnCalls.push(msg) } },
    on() {},
  }
  apply(disabled, {})
  const ok = warnCalls.length === 1 && warnCalls[0].includes('scriptsDir')
  ok
    ? pass('missing scriptsDir disables plugin with a warning')
    : fail('missing scriptsDir', JSON.stringify(warnCalls))
}

// ---- 8. plugin meta --------------------------------------------------------
name === 'dsh-notify-hooks'
  ? pass('plugin name is dsh-notify-hooks')
  : fail('plugin name', name)

rmSync(tmp, { recursive: true, force: true })

const failed = results.filter((r) => !r.ok).length
console.log(`\n${results.length - failed}/${results.length} passed`)
process.exit(failed === 0 ? 0 : 1)
