import { getLexicalTokens } from './lexical.js'
import { getSyntacticTokens } from './syntactic.js'

const expressions = [
  'title:"The Right Way" AND text:go',
  '"jakarta apache" AND "Apache Lucene"',
  '(jakarta OR apache) AND (website OR abc)',
  '\\(1\\+1\\)\\:2'
]

export const test = () => {
  const results = expressions.map(t => getSyntacticTokens(getLexicalTokens(t)))
  console.log(results)
  return results
}

export default test()