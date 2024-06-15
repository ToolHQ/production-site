/* eslint-disable @typescript-eslint/no-non-null-assertion */
import express, {
  Express,
  Request,
  Response,
  NextFunction,
  // Router,
  RequestHandler,
} from 'express';

import Logger from '@dnorio/logger';
import { logRequestsConstructor } from '@dnorio/logger/requestLoggerMiddleware';
import { setReqIdMiddleware } from '@dnorio/logger/setId';
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

import { router as todoRoutes } from './routes/todo.js';
import integrationRoutes from './routes/integration.js';
import { ValidationMiddlewareHandler } from './services/validations.js';

const { logger } = Logger();
const app = express();
const port = 3000;

app.use(setReqIdMiddleware);
app.use(express.json());
app.use(
  logRequestsConstructor({
    routesToIgnore: ['/health'],
    logResponseBody: false,
  })
);

app.use('/test', integrationRoutes);
app.use('/todos', todoRoutes);

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
    in: 'path',
    required: required.includes(key),
    schema: property,
  })) as SwaggerParameterObject[];
};

const addSchemaToLayer = (
  subLayer: ExpressLayer,
  pathMethodOperation: SwaggerOperationObject
) => {
  if (
    subLayer.name === 'validationMiddlewareHandler' &&
    (subLayer.handle as ValidationMiddlewareHandler).paramsSchemaName
  ) {
    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const paramsSchemaName = (subLayer.handle as ValidationMiddlewareHandler)
      .paramsSchemaName!;
    const paramsSchema = (subLayer.handle as ValidationMiddlewareHandler)
      .paramsSchema;
    pathMethodOperation.description = paramsSchemaName;
    pathMethodOperation.parameters = mapParamsSchemaToParameters(
      paramsSchema as JSONSchemaObject
    );
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

const createSwaggerOperationObject = () => {
  const pathMethodOperation: SwaggerOperationObject = {
    parameters: [],
    responses: {
      '200': {
        description: 'Success',
        content: {
          'application/json': {},
        },
      },
    },
  };
  return pathMethodOperation;
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
    },
  },
  routeSubPath?: string | null
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
          const pathMethodOperation = createSwaggerOperationObject();
          for (const subLayer of expressLayer.route.stack) {
            addSchemaToLayer(subLayer, pathMethodOperation);
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
      const match = expressLayer.regexp
        .toString()
        .match(/^\/\^\\\/(.*?)\\\/\?\(\?=\\\/|\$\)\/i$/);
      //   swaggerPath = swaggerPath.replace(paramPattern, `{${key.name}}`);
      processExpressStack(
        expressLayer.handle.stack,
        swaggerSetup,
        match ? `/${match[1]}` : null
      );
    } else if (
      expressLayer.name !== 'query' &&
      expressLayer.name !== 'expressInit'
    ) {
      if (expressLayer.regexp.source !== '^\\/?(?=\\/|$)' || routeSubPath) {
        const match = expressLayer.regexp
          .toString()
          .match(/^\/\^\\\/(.*?)\\\/\?\(\?=\\\/|\$\)\/i$/);
        let swaggerPath = match && match[1] ? `/${match[1]}` : '';
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

const addSwaggerToExpress = (app: Express) => {
  const swaggerSetup = processExpressStack(app._router.stack);
  app.use('/swagger-ui', getRouter({ content: JSON.stringify(swaggerSetup) }));
  const updatedSwaggerSetup = processExpressStack(app._router.stack);
  updateSwaggerContent(JSON.stringify(updatedSwaggerSetup));
};
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const healthCheck: express.RequestHandler<void> = (_, res) => {
  res.status(200).json({ message: 'Hello World!' });
};

app.get('/health', healthCheck);

addSwaggerToExpress(app);

// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use((error: Error, req: Request, res: Response, _2: NextFunction): void => {
  logger.errorEvent('Server ERROR', {
    method: req.method,
    path: req.path,
    name: error.name,
    stack: error.stack,
    message: error.message,
    cause: error.cause,
  });
  res.status(500).json({ message: error.message });
});

app.listen(port, () => {
  logger.infoEvent('Server started', { port });
});
