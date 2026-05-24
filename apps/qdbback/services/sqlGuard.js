const stripComments = (sql) => sql
  .replace(/\/\*[\s\S]*?\*\//g, ' ')
  .replace(/--[^\n\r]*/g, ' ')

/**
 * Permite apenas SELECT read-only no monitor admin (produção).
 * @param {string} sql
 */
export const isReadOnlySelect = (sql) => {
  const normalized = stripComments(String(sql || '')).trim()
  if (!/^select\b/i.test(normalized)) return false
  const forbidden = /\b(insert|update|delete|drop|alter|create|replace|attach|detach|reindex|vacuum|pragma)\b/i
  return !forbidden.test(normalized)
}
