'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

test('agent compact exige admin y encola solo un worker con sesión', (t) => {
  const bridge=fs.mkdtempSync(path.join(os.tmpdir(),'bridge-compact-'));
  t.after(()=>fs.rmSync(bridge,{recursive:true,force:true}));
  fs.mkdirSync(path.join(bridge,'runs'),{recursive:true});
  fs.mkdirSync(path.join(bridge,'sessions','codex-2'),{recursive:true});
  fs.writeFileSync(path.join(bridge,'admin'),'claude-1');
  fs.writeFileSync(path.join(bridge,'names.conf'),'/tmp/.codex=codex-2\n/tmp/.claude=claude-1\n');
  fs.writeFileSync(path.join(bridge,'runs','codex-2.pid'),String(process.pid));
  fs.writeFileSync(path.join(bridge,'runs','codex-2.state'),'status=idle\n');
  fs.writeFileSync(path.join(bridge,'sessions','codex-2','thread'),'thread-id');
  const script=path.resolve(__dirname,'../../scripts/agent');
  const run=(identity)=>spawnSync('bash',[script,'compact','codex-2'],{encoding:'utf8',env:{...process.env,BRIDGE_DIR:bridge,BRIDGE_NAME:identity}});
  assert.notEqual(run('codex-2').status,0);
  assert.equal(run('claude-1').status,0);
  assert.match(fs.readFileSync(path.join(bridge,'runs','codex-2.compact.request'),'utf8'),/requested_at=/);
});
