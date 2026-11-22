'use strict';

const CLAUDE_MODELS = ['default', 'sonnet', 'haiku', 'opus'];
const CLAUDE_EFFORTS = ['default', 'low', 'medium', 'high', 'xhigh', 'max'];
const CODEX_EFFORTS = ['default', 'none', 'minimal', 'low', 'medium', 'high', 'xhigh'];
const KIRO_EFFORTS = ['default', 'low', 'medium', 'high', 'xhigh', 'max'];

function effortOptions(kind) {
  if (kind === 'claude') return CLAUDE_EFFORTS;
  if (kind === 'codex') return CODEX_EFFORTS;
  if (kind === 'kiro' || kind === 'antigravity') return KIRO_EFFORTS;
  return [];
}

function modelOptions(kind, codexModels = []) {
  if (kind === 'claude') return CLAUDE_MODELS;
  if (kind === 'codex' || kind === 'kiro' || kind === 'antigravity' || kind === 'cursor') return [...new Set(['default', ...codexModels.filter((model) => /^[A-Za-z0-9._-]{1,80}$/.test(model))])];
  return [];
}

function validateControl(agent, request, codexModels = []) {
  if (!agent || agent.role === 'admin') return 'Los controles solo están disponibles para workers';
  if (request?.action === 'model') {
    if (!modelOptions(agent.kind, codexModels).includes(request.value)) return 'Modelo no permitido';
    if (request.value === 'opus' && request.confirmed !== true) return 'Opus requiere confirmación explícita';
    return '';
  }
  if (request?.action === 'effort') return effortOptions(agent.kind).includes(request.value) ? '' : 'Esfuerzo no permitido';
  if (request?.action === 'compact') return ['claude', 'codex', 'kiro', 'antigravity', 'cursor', 'qwen'].includes(agent.kind) ? '' : 'Tipo de agente no compatible';
  return 'Acción no permitida';
}

function authorizeAdminAction({ dashboardAdmin, recordedAdmin, sessionName, target }) {
  if (!dashboardAdmin || dashboardAdmin !== recordedAdmin) return 'El admin activo no coincide con el dashboard';
  if (sessionName !== dashboardAdmin) return 'Para cambiar workers, inicia el widget desde la sesión admin.';
  if (!target || target.role === 'admin') return 'Acción reservada a workers';
  return '';
}

module.exports = { effortOptions, modelOptions, validateControl, authorizeAdminAction };
