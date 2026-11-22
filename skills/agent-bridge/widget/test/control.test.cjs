'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { effortOptions, modelOptions, validateControl, authorizeAdminAction } = require('../src/control.cjs');

test('limita modelo Claude a sonnet/haiku salvo Opus confirmado', () => {
  const worker={role:'worker',kind:'claude'};
  assert.deepEqual(modelOptions('claude'),['default','sonnet','haiku','opus']);
  assert.equal(validateControl(worker,{action:'model',value:'opus'}),'Opus requiere confirmación explícita');
  assert.equal(validateControl(worker,{action:'model',value:'opus',confirmed:true}),'');
  assert.equal(validateControl(worker,{action:'model',value:'gpt-6-luna'}),'Modelo no permitido');
});

test('limita Codex a modelos locales visibles y niveles válidos por tipo', () => {
  assert.deepEqual(modelOptions('codex',['gpt-6-luna','bad model']),['default','gpt-6-luna']);
  assert.deepEqual(effortOptions('codex'),['default','none','minimal','low','medium','high','xhigh']);
  assert.equal(validateControl({role:'worker',kind:'codex'},{action:'effort',value:'max'}),'Esfuerzo no permitido');
  assert.match(validateControl({role:'admin',kind:'claude'},{action:'compact'}),/solo están disponibles/);
});

test('exige identidad admin coincidente y bloquea al propio admin como objetivo', () => {
  const base={dashboardAdmin:'claude-1',recordedAdmin:'claude-1',sessionName:'claude-1',target:{role:'worker'}};
  assert.equal(authorizeAdminAction(base),'');
  assert.match(authorizeAdminAction({...base,sessionName:'codex-1'}),/sesión admin/);
  assert.match(authorizeAdminAction({...base,target:{role:'admin'}}),/reservada a workers/);
  assert.match(authorizeAdminAction({...base,recordedAdmin:'codex-1'}),/no coincide/);
});

test('Kiro controla modelos anunciados, esfuerzo y compactación por handoff', () => {
  const kiro = { role: 'worker', kind: 'kiro' };
  assert.equal(validateControl(kiro, { action: 'model', value: 'claude-sonnet-4.5' }, ['claude-sonnet-4.5']), '');
  assert.match(validateControl(kiro, { action: 'model', value: 'not-listed' }, ['auto']), /Modelo/);
  assert.equal(validateControl(kiro, { action: 'effort', value: 'high' }), '');
  assert.equal(validateControl(kiro, { action: 'compact' }), '');
});
