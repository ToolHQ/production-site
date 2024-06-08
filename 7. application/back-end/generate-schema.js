import fs from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import tsj from 'typescript-json-schema';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Settings for the JSON schema generation
const settings = {
  required: true,
};

// Path to the tsconfig file
const tsconfig = 'tsconfig.json';

// Specify the type(s) you want to generate schema for
const types = ['DatabaseConfigParams'];

// Generate the schema(s)
const program = tsj.getProgramFromFiles(
  [`${__dirname}/src/types.ts`],
  tsconfig
);
for (const type of types) {
  const schema = tsj.generateSchema(program, type, settings);
  fs.writeFileSync(`schemas/${type}.json`, JSON.stringify(schema, null, 2));
}

fs.writeFileSync(
  `src/exportedSchemas.ts`,
  `export type ExportedSchemas = ${types
    .map((type) => JSON.stringify(type))
    .join(' | ')};\n`
);
// console.log('JSON schema generated successfully.\n');
