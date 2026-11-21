'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { parseClaude, parseCodex, redact, tail, selectEvents } = require('../../scripts/bridge-feed');
test('parsea mensajes Claude, herramienta y resultado', () => {
  assert.equal(parseClaude(JSON.stringify({type:'user',timestamp:'2026-01-01T00:00:00Z',message:{content:[{type:'text',text:'hola'}]}}))[0].role,'order');
  assert.equal(parseClaude(JSON.stringify({type:'assistant',message:{content:[{type:'tool_use',name:'Read',input:{path:'a'}}]}}))[0].role,'tool');
  assert.equal(parseClaude(JSON.stringify({type:'result',result:'fin'}))[0].role,'result');
});
test('parsea formato Codex', () => {
  const order = parseCodex(JSON.stringify({timestamp:'2026-01-01T00:00:00Z',type:'response_item',payload:{type:'message',role:'user',content:[{type:'input_text',text:'orden'}]}}));
  const assistant = parseCodex(JSON.stringify({timestamp:'2026-01-01T00:00:02Z',type:'response_item',payload:{type:'message',role:'assistant',content:[{type:'output_text',text:'Voy a revisar'}]}}));
  const tool = parseCodex(JSON.stringify({timestamp:'2026-01-01T00:00:03Z',type:'response_item',payload:{type:'custom_tool_call',name:'exec',input:'ls'}}));
  const objectTool = parseCodex(JSON.stringify({type:'response_item',payload:{type:'custom_tool_call',name:'exec',input:{cmd:'pwd',args:['-P']}}}));
  assert.deepEqual([order[0].role, assistant[0].role, tool[0].role], ['order','assistant','tool']);
  assert.equal(objectTool[0].text, '{"cmd":"pwd","args":["-P"]}');
  assert.equal(parseCodex(JSON.stringify({type:'response_item',payload:{type:'message',role:'developer',content:[{text:'contexto'}]}})).length,0);
});
test('elimina envoltorio del runner y ruido AGENTS', () => {
  const wrapped = "You are worker 'codex-2' in a team.\n\nOrder:\n# AGENTS.md instructions\nmetadata\n<environment_context>\nvariables\n</environment_context>\n\nOrder real: arregla esto";
  assert.equal(parseClaude(JSON.stringify({type:'user',message:{content:wrapped}}))[0].text, 'Order real: arregla esto');
  assert.equal(parseClaude(JSON.stringify({type:'user',message:{content:'# AGENTS.md instructions\ncontext\n<environment_context>'}})).length,0);
});
test('límite toma los últimos N después de ordenar y tail ignora JSONL parcial', () => {
  const events = ['18:48','15:57','18:47','18:49','18:46'].map((t,i)=>({ts:`2026-01-01T${t}:00Z`,text:String(i)}));
  assert.deepEqual(selectEvents(events,{limit:2}).map(e=>e.ts), ['2026-01-01T18:48:00Z','2026-01-01T18:49:00Z']);
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'feed-')); const file=path.join(dir,'rollout.jsonl');
  fs.writeFileSync(file, `${JSON.stringify({type:'event_msg',timestamp:'ok'})}\n{"type":"partial"`);
  assert.equal(tail(file).length,1); fs.rmSync(dir,{recursive:true,force:true});
});
test('redacta tokens e limita texto', () => {
  assert.match(redact('Bearer abc sk-1234567890 ghp_abcdefghijk KEY=secret'), /REDACTED/);
  assert.equal(parseClaude(JSON.stringify({type:'user',message:{content:'x'.repeat(2100)}}))[0].text.length,2000);
});
