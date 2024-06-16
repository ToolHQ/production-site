/* eslint-disable @typescript-eslint/no-non-null-assertion */
import { Express, RequestHandler } from 'express';

import {
  getRouter,
  updateSwaggerContent,
  JSONSchemaObject,
  SwaggerParameterObject,
  SwaggerOperationObject,
  SwaggerValidOperations,
  swaggerValidOperationsList,
  OpenAPIObject,
  ExpressMethodValues,
} from '@dnorio/swagger-router';

import { ValidationMiddlewareHandler } from './validations.js';

type ExpressRoute = {
  methods: {
    [key in ExpressMethodValues]?: string;
  };
  path: string;
  stack: ExpressLayer[];
};
type ExpressLayer = {
  handle: RequestHandler & { stack?: ExpressLayer[] };
  keys: { name: string; optional: boolean; offset: number }[];
  method: ExpressMethodValues;
  name: string;
  params: undefined;
  path: undefined;
  regexp: RegExp;
  route?: ExpressRoute;
};
type ExpressLayerWithRoute = Omit<ExpressLayer, 'route'> & {
  route: ExpressRoute;
};

const mapParamsSchemaToParameters: (
  paramsSchema: JSONSchemaObject
) => SwaggerParameterObject[] = (paramsSchema) => {
  const required = paramsSchema.required || [];
  const properties = paramsSchema.properties || {};
  return Object.entries(properties).map(([key, property]) => ({
    name: key,
    description: property.description,
    in: 'path',
    required: required.includes(key),
    schema: property,
  })) as SwaggerParameterObject[];
};

const addQuerySchemaToParameters: (
  querySchema: JSONSchemaObject,
  parameters?: SwaggerParameterObject[]
) => SwaggerParameterObject[] = (querySchema, parameters) => {
  const newParameters = parameters || [];
  const required = querySchema.required || [];
  const properties = querySchema.properties || {};
  return newParameters.concat(
    Object.entries(properties).map(([key, property]) => ({
      name: key,
      description: property.description,
      in: 'query',
      required: required.includes(key),
      schema: property,
    })) as SwaggerParameterObject[]
  );
};

const addSchemaToLayer = (
  subLayer: ExpressLayer,
  op: SwaggerOperationObject,
  aboveLayer: ExpressLayer,
  routerKeys?: { name: string; optional: boolean; offset: number }[],
  swaggerSetup?: OpenAPIObject
  // method?: ExpressMethodValues
) => {
  if (subLayer.name === 'validationMiddlewareHandler') {
    const handler = subLayer.handle as ValidationMiddlewareHandler;
    // Process params schema
    if (handler.paramsSchema && handler.paramsSchemaName !== 'Empty') {
      const { paramsSchema, paramsSchemaName } = handler;
      op.description = paramsSchema.description || paramsSchemaName;
      op.summary = paramsSchema.title;
      op.parameters = mapParamsSchemaToParameters(
        paramsSchema as JSONSchemaObject
      );
    }
    // Process body schema
    if (handler.bodySchema && handler.bodySchemaName !== 'Empty') {
      const { bodySchema, bodySchemaName } = handler;
      op.description = bodySchema.description || bodySchemaName;
      op.summary = bodySchema.title;
      op.requestBody = {
        required: true,
        description: bodySchema.description,
        content: {
          'application/json': {
            schema: bodySchema,
          },
        },
      };
    }
    // Process query schema
    if (handler.querySchema && handler.querySchemaName !== 'Empty') {
      const { querySchema, querySchemaName } = handler;
      op.description = querySchema.description || querySchemaName;
      op.summary = querySchema.title;
      op.parameters = addQuerySchemaToParameters(
        querySchema as JSONSchemaObject,
        op.parameters as SwaggerParameterObject[]
      );
    }
    // Adds responses
    if (handler.responses) {
      op.responses = handler.responses;
    }
    // Adds definitions
    if (handler.schemaDefinitions) {
      swaggerSetup!.components!.schemas = {
        ...swaggerSetup?.components?.schemas,
        ...handler.schemaDefinitions,
      };
    }
  } else if (!op.parameters) {
    op.parameters = [];
    if (routerKeys) {
      for (const key of routerKeys) {
        op.parameters.push({
          name: key.name,
          in: 'path',
          required: !key.optional,
          schema: { type: 'string' },
        });
      }
    }
    for (const key of aboveLayer.keys) {
      op.parameters.push({
        name: key.name,
        in: 'path',
        required: !key.optional,
        schema: { type: 'string' },
      });
    }
  }
};

const extractPath = (
  expressLayer: ExpressLayerWithRoute,
  routeSubPath?: string | null
): string => {
  let swaggerPath = expressLayer.route.path;
  const keys = expressLayer.keys;
  keys.sort((a, b) => b.offset - a.offset);
  for (const key of keys) {
    // Replace the parameter at the specific offset
    const paramPattern = new RegExp(`:${key.name}(\\([^)]*\\))?`, 'g');
    swaggerPath = swaggerPath.replace(paramPattern, `{${key.name}}`);
  }
  if (swaggerPath === '/') {
    swaggerPath = '';
  }
  if (routeSubPath) {
    swaggerPath = `${routeSubPath}${swaggerPath}`;
  }
  return swaggerPath;
};

const createSwaggerOperationObject = (tagName?: string) => {
  const pathMethodOperation: SwaggerOperationObject = {
    responses: {
      '200': {
        description: 'Success',
        content: {
          'application/json': {},
        },
      },
    },
  };
  if (tagName) {
    pathMethodOperation.tags = [tagName];
  }
  return pathMethodOperation;
};

const extractRoutePathRegex = (expressLayer: ExpressLayer) => {
  let swaggerPath = expressLayer.regexp.source;
  const keys = expressLayer.keys;
  keys.sort((a, b) => a.offset - b.offset);
  for (const key of keys) {
    // Replace the non capturing parameter at the specific offset
    swaggerPath = swaggerPath.replace('(?:([^\\/]+?))', `{${key.name}}`);
  }
  swaggerPath = swaggerPath
    .replace('\\/?', '')
    .replace('(?=\\/|$)', '')
    .replace('^\\/', '/')
    .replaceAll('\\/', '/');
  return swaggerPath;
};

const processExpressStack = (
  stack: ExpressLayer[],
  swaggerSetup: OpenAPIObject = {
    openapi: '3.0.3',
    info: {
      title: 'dnorio my-site API',
      description: 'dnorio my-site API',
      version: '1.0.0',
      contact: {
        email: 'danieltakasu@gmail.com',
      },
    },
    servers: [
      {
        url: '/',
        description: 'Local',
      },
      {
        url: '/api',
        description: 'Default',
      },
    ],
    tags: [],
    paths: {},
    components: {
      securitySchemes: {
        Authorization: {
          description: 'User JWT token',
          type: 'apiKey',
          in: 'header',
          name: 'Authorization',
        },
      },
      schemas: {},
    },
  },
  routeSubPath?: string | null,
  tagName?: string,
  routerKeys?: { name: string; optional: boolean; offset: number }[]
) => {
  for (const expressLayer of stack) {
    if (expressLayer.route) {
      const swaggerPath = extractPath(
        expressLayer as ExpressLayerWithRoute,
        routeSubPath
      );
      if (!swaggerSetup.paths[swaggerPath]) {
        swaggerSetup.paths[swaggerPath] = {};
      }
      for (const routeMethodsData of Object.entries(
        expressLayer.route.methods
      )) {
        const method = routeMethodsData[0] as ExpressMethodValues;
        const active = routeMethodsData[1] as unknown as boolean;
        if (active) {
          const pathMethodOperation = createSwaggerOperationObject(tagName);
          for (const subLayer of expressLayer.route.stack) {
            addSchemaToLayer(
              subLayer,
              pathMethodOperation,
              expressLayer,
              routerKeys,
              swaggerSetup
              // method
            );
          }
          if (method === '_all') {
            for (const validOperation of swaggerValidOperationsList) {
              swaggerSetup.paths[swaggerPath]![validOperation] =
                pathMethodOperation as SwaggerOperationObject;
            }
          } else if (
            swaggerValidOperationsList.includes(
              method as SwaggerValidOperations
            )
          ) {
            swaggerSetup.paths[swaggerPath]![method as SwaggerValidOperations] =
              pathMethodOperation as SwaggerOperationObject;
          }
        }
      }
    } else if (expressLayer.name === 'router' && expressLayer.handle.stack) {
      const routePath = extractRoutePathRegex(expressLayer);
      let routerTagName: string | undefined;
      if (routePath) {
        routerTagName = `${routePath[1]?.toUpperCase()}${routePath.slice(2)}`;
        if (!swaggerSetup.tags?.find((tag) => tag.name === routerTagName)) {
          swaggerSetup.tags?.push({ name: routerTagName });
        }
      }
      processExpressStack(
        expressLayer.handle.stack,
        swaggerSetup,
        routePath,
        routerTagName,
        expressLayer.keys
      );
    } else if (
      expressLayer.name !== 'query' &&
      expressLayer.name !== 'expressInit'
    ) {
      if (expressLayer.regexp.source !== '^\\/?(?=\\/|$)' || routeSubPath) {
        let swaggerPath = extractRoutePathRegex(expressLayer);
        if (routeSubPath) {
          swaggerPath = `${routeSubPath}${swaggerPath}`;
        }
        if (swaggerPath) {
          if (!swaggerSetup.paths[swaggerPath]) {
            swaggerSetup.paths[swaggerPath] = {};
          }
          const pathMethodOperation = createSwaggerOperationObject();
          for (const validOperation of swaggerValidOperationsList) {
            swaggerSetup.paths[swaggerPath]![validOperation] =
              pathMethodOperation as SwaggerOperationObject;
          }
        }
      }
    }
  }
  return swaggerSetup;
};

export const addSwaggerToExpress = (app: Express) => {
  const swaggerSetup = processExpressStack(app._router.stack);
  app.use('/swagger-ui', getRouter({ content: JSON.stringify(swaggerSetup) }));
  const updatedSwaggerSetup = processExpressStack(app._router.stack);
  updateSwaggerContent(JSON.stringify(updatedSwaggerSetup));
};
