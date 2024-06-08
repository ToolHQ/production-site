import path, { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';

import Ajv from 'ajv';
import addFormats from 'ajv-formats';

import Logger from '@dnorio/logger';

import { RequestHandler } from 'express';
import { ExportedSchemas } from '../exportedSchemas.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const cwd = path.resolve(__dirname);

const { logger } = Logger();

const ajv = new Ajv({
  logger: {
    log: logger.infoEvent.bind(null, 'AJV Validation INFO'),
    warn: logger.infoEvent.bind(null, 'AJV Validation WARN'),
    error: logger.infoEvent.bind(null, 'AJV Validation ERROR'),
  },
  allErrors: false,
  removeAdditional: true,
});
addFormats(ajv);

type OpenApiSchema = {
  [key: string]: unknown;
};

export const getValidationMiddleware = (openApiSchema: OpenApiSchema) => {
  const validate = ajv.compile(openApiSchema);
  const handler: RequestHandler = (req, res, next) => {
    const data = {
      params: req.params,
      headers: req.headers,
      body: req.body,
      query: req.query,
      // file: req.file,
    };
    if (validate(data)) {
      next();
    } else {
      res.status(400).json({
        errors: validate.errors,
      });
    }
  };
  return handler;
};

const cachedSubSchemas = new Map<ExportedSchemas, OpenApiSchema>();

const getSubSchema = (exportedSchemaName: ExportedSchemas): OpenApiSchema => {
  const cachedSchema = cachedSubSchemas.get(exportedSchemaName);
  if (cachedSchema) {
    return cachedSchema;
  }
  const schema = JSON.parse(
    readFileSync(
      path.join(cwd, `../../schemas/${exportedSchemaName}.json`)
    ).toString('utf-8')
  ) as OpenApiSchema;
  cachedSubSchemas.set(exportedSchemaName, schema);
  return schema;
};

export const validateMiddleware = (paramsSchema: ExportedSchemas) => {
  const schema: {
    $schema: 'http://json-schema.org/draft-07/schema#';
    type: 'object';
    properties: {
      params?: {
        [key: string]: unknown;
      };
    };
    required: ('params' | 'headers' | 'body' | 'query')[];
  } = {
    $schema: 'http://json-schema.org/draft-07/schema#',
    type: 'object',
    properties: {},
    required: [],
  };
  if (paramsSchema) {
    const subSchema = getSubSchema(paramsSchema);
    schema.properties.params = subSchema;
    schema.required.push('params');
  }
  return getValidationMiddleware(schema);
};

export const defaultResponses = {
  200: {
    description: 'OK',
  },
  400: {
    description:
      'Validation Error (happens when some basic request payload contract is not fulfilled).',
  },
  401: {
    description: 'Unauthorized',
  },
  403: {
    description: 'Forbidden',
  },
  500: {
    description: 'Internal Server Error (Please, report it if happens).',
  },
};
