// Смоук-тест Spirit Catchers: компиляция всех .luau настоящим Luau (WASM) и прогон сценария
// сервер + клиент на эмуляторе Roblox. Запуск: node tools/sim/run.mjs (из папки spirit-catchers),
// пакет luau-web должен быть установлен (NODE_PATH или node_modules рядом).
import { LuauState } from 'luau-web'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const here = path.dirname(fileURLToPath(import.meta.url))
const src = path.resolve(here, '../../src')
const files = []
const walk = d => { for (const f of fs.readdirSync(d)) { const p = path.join(d, f); fs.statSync(p).isDirectory() ? walk(p) : p.endsWith('.luau') && files.push(p) } }
walk(src)

const st = await LuauState.createAsync()
try { st.env.setreadonly(st.env.global, false) } catch (e) { console.log('setreadonly:', e.message) }
let compileFail = 0
for (const f of files) {
  const r = st.loadstring(fs.readFileSync(f, 'utf8'), path.basename(f), false)
  if (typeof r === 'string') { compileFail++; console.log('COMPILE FAIL', path.relative(src, f), r) }
}
if (compileFail) process.exit(1)

let bundle = fs.readFileSync(path.join(here, 'roblox.luau'), 'utf8').replace(/\nreturn SIM\s*$/, '\n')
bundle += '\nlocal __defs = {}\nlocal require\n'
for (const f of files) {
  const key = path.relative(src, f).replace(/\\/g, '/').replace(/\.luau$/, '')
  bundle += `__defs[${JSON.stringify(key)}] = function(script)\n${fs.readFileSync(f, 'utf8')}\nend\n`
}
bundle += fs.readFileSync(path.join(here, 'scenario.luau'), 'utf8')
fs.writeFileSync(path.join(here, '.bundle.luau'), bundle)

const fn = st.loadstring(bundle, 'bundle', false)
if (typeof fn === 'string') { console.log('BUNDLE COMPILE FAIL', fn); process.exit(1) }
let sim
try { sim = await fn() } catch (e) { console.log('SCENARIO CRASH', e.message || e); process.exit(1) }
const S = Array.isArray(sim) ? sim[0] : sim
const get = (t, k) => (t && typeof t.get === 'function') ? t.get(k) : t[k]
const toArr = t => { const out = []; if (!t) return out; for (let i = 1; ; i++) { const v = get(t, i); if (v === undefined || v === null) break; out.push(v) } return out }
for (const l of toArr(get(S, 'log'))) console.log(l)
const errs = toArr(get(S, 'errors'))
console.log(`\n${errs.length} ошибок`)
for (const e of errs.slice(0, 40)) console.log('---\n' + e)
process.exit(errs.length ? 2 : 0)
