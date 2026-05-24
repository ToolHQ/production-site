const lexicalClassifications = {
  letter: 'letter',
  digit: 'digit',
  space: 'space',
  colon: ':',
  doubleQuote: '"',
  plus: '+',
  minus: '-',
  leftParenthese: '(',
  rightParenthese: ')',
  leftSquareBracket: '[',
  rightSquareBracket: ']',
  leftCurlyBracket: '{',
  rightCurlyBracket: '}',
  expression: 'expression', // Phase 2
  opAND: 'AND', // Phase 3
  opOR: 'OR',
}

const lexicalTest = {
  letter: /[a-zA-Z]|ã|â|á|à|í|ê|é|õ|ô|ó|Ã|Â|Á|À|Í|Ê|É|Õ|Ô|Ó/,
  digit: /\d/,
  space: /\t| /,
  colon: ':',
  doubleQuote: '"',
  scape: '\\',
  plus: '+',
  minus: '-',
  leftParenthese: '(',
  rightParenthese: ')',
  leftSquareBracket: '[',
  rightSquareBracket: ']',
  leftCurlyBracket: '{',
  rightCurlyBracket: '}',
  opAND: 'AND',
  opOR: 'OR',
}

/**
 * @typedef {Object} Token
 * @property {Number} initialPos
 * @property {Number} finalPos
 * @property {String} str
 * @property {String} type
 */

/**
 * Classifies by char value almost, considers \ only as special
 * @param {String} input
 */
const lexicalStage1 = (input) => {
  let pos = 0
  const tokens = []
  let scape = false
  for (const char of input) { // unicode iteration
    if (scape) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.letter,
      })
      scape = false
    } else if (lexicalTest.letter.test(char)) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.letter,
      })
    } else if (lexicalTest.digit.test(char)) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.digit,
      })
    } else if (lexicalTest.space.test(char)) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.space,
      })
    } else if (char === lexicalTest.colon) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.colon,
      })
    } else if (char === lexicalTest.doubleQuote) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.doubleQuote,
      })
    } else if (char === lexicalTest.plus) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.plus,
      })
    } else if (char === lexicalTest.minus) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.minus,
      })
    } else if (char === lexicalTest.leftParenthese) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.leftParenthese,
      })
    } else if (char === lexicalTest.rightParenthese) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.rightParenthese,
      })
    } else if (char === lexicalTest.leftSquareBracket) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.leftSquareBracket,
      })
    } else if (char === lexicalTest.rightSquareBracket) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.rightSquareBracket,
      })
    } else if (char === lexicalTest.leftCurlyBracket) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.leftCurlyBracket,
      })
    } else if (char === lexicalTest.rightCurlyBracket) {
      tokens.push({
        initialPos: pos,
        finalPos: pos,
        str: char,
        type: lexicalClassifications.rightCurlyBracket,
      })
    } else if (char === lexicalTest.scape) {
      scape = true
    } else {
      throw Error(`LexicalError at pos ${pos}. Invalid token "${char}".`)
    }
    pos++
  }
  return tokens
}

/**
 * Groups letters and digits into expressions
 * @param {Token[]} stage1Tokens
 */
const lexicalStage2 = (stage1Tokens) => {
  const tokens = []
  let newTextToken
  for (const token of stage1Tokens) {
    if (token.type === lexicalClassifications.letter || token.type === lexicalClassifications.digit) {
      if (!newTextToken) {
        newTextToken = {
          initialPos: token.initialPos,
          finalPos: token.finalPos,
          str: token.str,
          type: lexicalClassifications.expression,
        }
      } else {
        newTextToken.finalPos = token.finalPos
        newTextToken.str += token.str
      }
    } else if (token.type === lexicalClassifications.space) {
      if (newTextToken) {
        tokens.push(newTextToken)
        newTextToken = null
      }
      tokens.push(token)
    } else {
      if (newTextToken) {
        tokens.push(newTextToken)
        newTextToken = null
      }
      tokens.push(token)
    }
  }
  if (newTextToken) {
    tokens.push(newTextToken)
  }
  return tokens
}

/**
 * Removes doubleQuotes and spaces
 * @param {Token[]} stage2Tokens
 */
const lexicalStage3 = (stage2Tokens) => {
  const tokens = []
  let newTextToken
  let quoting = false
  for (const token of stage2Tokens) {
    if (quoting) {
      if (token.type === lexicalClassifications.doubleQuote) {
        quoting = false
        newTextToken.finalPos = token.finalPos
        newTextToken.quoted = true
        tokens.push(newTextToken)
        newTextToken = null
      } else {
        newTextToken.finalPos = token.finalPos
        newTextToken.str += token.str
      }
    } else if (token.type === lexicalClassifications.doubleQuote) {
      quoting = true
      newTextToken = {
        initialPos: token.initialPos,
        finalPos: token.finalPos,
        str: '',
        type: lexicalClassifications.expression,
      }
    } else if (token.type !== lexicalClassifications.space) {
      if (token.type === lexicalClassifications.expression) {
        if (token.str === lexicalTest.opAND) {
          token.type = lexicalClassifications.opAND
        } else if (token.str === lexicalTest.opOR) {
          token.type = lexicalClassifications.opOR
        }
      }
      tokens.push(token)
    }
  }
  if (quoting) {
    throw Error(`LexicalError at pos ${newTextToken.finalPos}. Unexpected end of input (Are you missing a " ?).`)
  }
  if (newTextToken) {
    tokens.push(newTextToken)
  }
  return tokens
}

export const getLexicalTokens = (input = '') => {
  const stage1Tokens = lexicalStage1(input)
  const stage2Tokens = lexicalStage2(stage1Tokens)
  return lexicalStage3(stage2Tokens)
}
