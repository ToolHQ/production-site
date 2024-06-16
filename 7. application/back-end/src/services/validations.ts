import path, { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';

import Ajv from 'ajv';
import addFormats from 'ajv-formats';

import Logger from '@dnorio/logger';

import { RequestHandler } from 'express';
import { ExportedSchemas, SchemaTypes } from '../exportedSchemas.js';
import { JSONSchema, SwaggerResponsesObject } from '@dnorio/swagger-router';

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

export type ValidationMiddlewareHandler = RequestHandler & {
  paramsSchemaName?: string;
  paramsSchema?: JSONSchema;
  bodySchemaName?: string;
  bodySchema?: JSONSchema;
  querySchemaName?: string;
  querySchema?: JSONSchema;
  responses?: SwaggerResponsesObject;
};
export const getValidationMiddleware = (openApiSchema: JSONSchema) => {
  const validate = ajv.compile(openApiSchema);
  const validationMiddlewareHandler: ValidationMiddlewareHandler = (
    req,
    res,
    next
  ) => {
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
  return validationMiddlewareHandler;
};

const cachedSubSchemas = new Map<ExportedSchemas, JSONSchema>();

const getSubSchema = (exportedSchemaName: ExportedSchemas): JSONSchema => {
  const cachedSchema = cachedSubSchemas.get(exportedSchemaName);
  if (cachedSchema) {
    return cachedSchema;
  }
  const schema = JSON.parse(
    readFileSync(
      path.join(cwd, `../../schemas/${exportedSchemaName}.json`)
    ).toString('utf-8')
  ) as JSONSchema;
  cachedSubSchemas.set(exportedSchemaName, schema);
  return schema;
};

export const validateMiddleware = <T extends keyof SchemaTypes>(
  paramsSchema?: ExportedSchemas,
  bodySchema?: ExportedSchemas,
  querySchema?: ExportedSchemas,
  responseSchema?: ExportedSchemas
): RequestHandler<SchemaTypes[T], SchemaTypes[T], SchemaTypes[T]> => {
  const schema: {
    $schema: 'http://json-schema.org/draft-07/schema#';
    type: 'object';
    properties: {
      params?: JSONSchema;
      body?: JSONSchema;
      query?: JSONSchema;
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
  if (bodySchema) {
    const subSchema = getSubSchema(bodySchema);
    schema.properties.body = subSchema;
    schema.required.push('body');
  }
  if (querySchema) {
    const subSchema = getSubSchema(querySchema);
    schema.properties.query = subSchema;
    schema.required.push('query');
  }
  const validationMiddleware = getValidationMiddleware(schema);
  validationMiddleware.paramsSchemaName = paramsSchema;
  validationMiddleware.paramsSchema = schema.properties.params;
  validationMiddleware.bodySchemaName = bodySchema;
  validationMiddleware.bodySchema = schema.properties.body;
  validationMiddleware.querySchemaName = querySchema;
  validationMiddleware.querySchema = schema.properties.query;
  validationMiddleware.responses = {
    400: {
      description: 'Validation Error',
      content: {
        'application/json': {
          schema: {
            type: 'object',
            properties: {
              errors: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    instancePath: { type: 'string' },
                    schemaPath: { type: 'string' },
                    keyword: { type: 'string' },
                    params: {
                      type: 'object',
                      properties: {
                        allowedValue: { type: 'string' },
                      },
                      required: [],
                    },
                    message: { type: 'string' },
                  },
                  required: ['instancePath', 'schemaPath', 'message'],
                },
              },
            },
            required: ['errors'],
          },
        },
      },
    },
  };
  if (responseSchema) {
    validationMiddleware.responses[200] = {
      description: 'Success',
      content: {
        'application/json': {
          schema: getSubSchema(responseSchema),
        },
      },
    };
  }
  return validationMiddleware as unknown as RequestHandler<
    SchemaTypes[T],
    SchemaTypes[T],
    SchemaTypes[T]
  >;
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
