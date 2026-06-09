/**
 * @param {import('./lexical').Token} token
 */
const preced = (tokenType) => {
  if (tokenType === 'OR') {
    return 1
  } if (tokenType === 'AND') {
    return 2
  } if (tokenType === ':') {
    return 3
  }
  return 0
}

/**
 * @param {import('./lexical').Token[]} infixTokens
 */
const inToPost = (infixTokens) => {
  const stk = []
  const postfix = []
  const parenthesisCheckStk = []
  // Check balanced parenthesis
  for (const infixToken of infixTokens) {
    if (infixToken.type === '(') {
      parenthesisCheckStk.push(infixToken)
    } else if (infixToken.type === ')') {
      if (!parenthesisCheckStk.length) {
        throw Error(`Syntax error: unexpected ')' at ${infixToken.initialPos} (Are you missing a left parenthesis?).`)
      }
      parenthesisCheckStk.pop()
    }
  }
  if (parenthesisCheckStk.length) {
    throw Error('Syntax error: unexpected end of input (Are you missing a right parenthesis?).')
  }

  for (const infixToken of infixTokens) {
    if (infixToken.type === 'expression') { // operands
      postfix.push(infixToken)
    } else if (infixToken.type === '(') {
      stk.push({ type: '(' })
    } else if (infixToken.type === ')') {
      while (stk.length && stk[stk.length - 1].type !== '(') {
        postfix.push(stk.pop())
      }
      stk.pop() // removes '('
    } else if ([':', 'AND', 'OR'].includes(infixToken.type)) { // operators
      while (stk.length && !['(', ')'].includes(stk[stk.length - 1].type) && preced(infixToken.type) <= preced(stk[stk.length - 1].type)) {
        postfix.push(stk.pop())
      }
      stk.push(infixToken)
    } else {
      throw Error(`Syntax error: unexpected token of type ${infixToken.type}`)
    }
  }

  while (stk.length) {
    postfix.push(stk.pop())
  }

  return postfix
}

/**
 * @param {import('./lexical').Token[]} lexicalTokens
 */
const syntacticStage1 = (lexicalTokens) => {
  return inToPost(lexicalTokens)
}

export const getSyntacticTokens = (lexicalTokens) => {
  const stage1Tokens = syntacticStage1(lexicalTokens)
  return stage1Tokens
}
