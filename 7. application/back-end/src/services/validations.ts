import path, { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';

import Ajv from 'ajv';
import addFormats from 'ajv-formats';

import Logger from '@dnorio/logger';

import { RequestHandler } from 'express';
import { ExportedSchemas, SchemaTypes } from '../exportedSchemas.js';
import {
  IANAHttpStatusCode,
  JSONSchema,
  SwaggerResponsesObject,
} from '@dnorio/swagger-router';

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
  schemaDefinitions?: { [key: string]: JSONSchema };
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

const adjustJSONSchemaRefsToOAS3 = (schema: JSONSchema) => {
  if (schema.type === 'object') {
    for (const propertySchema of Object.values(schema.properties)) {
      if (propertySchema.$ref) {
        propertySchema.$ref = propertySchema.$ref.replace(
          '#/definitions/',
          '#/components/schemas/'
        ); // Conformance from OpenAPI 2.0 to OpenAPI 3.0 spec
      } else if (
        propertySchema.type === 'object' ||
        propertySchema.type === 'array'
      ) {
        adjustJSONSchemaRefsToOAS3(propertySchema);
      }
    }
  } else if (schema.type === 'array') {
    if (schema.items?.$ref) {
      schema.items.$ref = schema.items.$ref.replace(
        '#/definitions/',
        '#/components/schemas/'
      ); // Conformance from OpenAPI 2.0 to OpenAPI 3.0 spec
    } else if (
      schema.items &&
      (schema.items.type === 'object' || schema.items.type === 'array')
    ) {
      adjustJSONSchemaRefsToOAS3(schema.items);
    }
  }
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
  validationMiddleware.schemaDefinitions = {};
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
    const schema = getSubSchema(responseSchema);
    adjustJSONSchemaRefsToOAS3(schema);
    let statusCode: IANAHttpStatusCode = 200;
    let statusDescription = 'Success';
    const contentType =
      schema.type === 'string' ? 'text/plain' : 'application/json';
    const matches = /(?<statusCode>\d{3}) *- *(?<statusDescription>.+)/.exec(
      String(schema.description)
    );
    if (matches?.groups) {
      const { groups } = matches;
      statusCode = Number(groups.statusCode) as IANAHttpStatusCode;
      // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
      statusDescription = groups.statusDescription!;
    }
    validationMiddleware.responses[statusCode] = {
      description: statusDescription,
      content: {
        [contentType]: {
          schema,
        },
      },
    };
    if (schema.definitions) {
      // Collect definitions from Responses
      validationMiddleware.schemaDefinitions = {
        ...validationMiddleware.schemaDefinitions,
        ...schema.definitions,
      };
      delete schema.definitions;
    }
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
