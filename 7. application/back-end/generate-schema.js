import fs from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import ts from 'typescript';
import tsj from 'typescript-json-schema';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Settings for the JSON schema generation
const settings = {
  required: true,
  // uniqueNames: true,
};

// Path to the tsconfig file
const tsconfig = 'tsconfig.json';

// Options for the TypeScript compiler
const compilerOptions = {
  target: 99,
  module: 99,
};

const sourceFile = `${__dirname}/src/types.ts`;

// Create a Program instance
const program = ts.createProgram([sourceFile], compilerOptions);

// Get all exported interface or type names
const typeNames = [];
const sourceFiles = program.getSourceFiles();
for (const sourceF of sourceFiles) {
  if (!sourceF.isDeclarationFile) {
    ts.forEachChild(sourceF, (node) => {
      if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) {
        if (
          node.modifiers &&
          node.modifiers.some(
            (modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword
          )
        ) {
          typeNames.push(node.name.escapedText);
        }
      }
    });
  }
}

// Generate the schema(s)
const tsjProgram = tsj.getProgramFromFiles(
  [`${__dirname}/src/types.ts`],
  tsconfig
);
for (const type of typeNames) {
  const schema = tsj.generateSchema(tsjProgram, type, settings);
  fs.writeFileSync(`schemas/${type}.json`, JSON.stringify(schema, null, 2));
}

const exportedSchemasTsContent = `import {${typeNames
  .map((type) => `\n  ${type}`)
  .join(',')}\n} from './types.js';\nexport type ExportedSchemas = ${typeNames
  .map((type) => JSON.stringify(type))
  .join(' | ')};\nexport type SchemaTypes = {${typeNames
  .map((type) => `\n  ${type}: ${type}`)
  .join(',')}\n};\n`;
fs.writeFileSync(`src/exportedSchemas.ts`, exportedSchemasTsContent);
// console.log('JSON schema generated successfully.\n');
