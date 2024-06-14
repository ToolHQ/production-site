/* eslint-disable @typescript-eslint/no-non-null-assertion */
import express, {
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

const processRouters = (
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
        url: '/api',
        description: 'Default',
      },
      {
        url: '/',
        description: 'Local',
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
      let swaggerPath = expressLayer.route.path;
      const keys = expressLayer.keys;
      keys.sort((a, b) => b.offset - a.offset);
      for (const key of keys) {
        // Replace the parameter at the specific offset
        const paramPattern = new RegExp(`:${key.name}(\\([^)]*\\))?`, 'g');
        swaggerPath = swaggerPath.replace(paramPattern, `{${key.name}}`);
      }
      if (routeSubPath) {
        swaggerPath = `${routeSubPath}${swaggerPath}`;
      }
      if (!swaggerSetup.paths[swaggerPath]) {
        swaggerSetup.paths[swaggerPath] = {};
      }
      for (const routeMethodsData of Object.entries(
        expressLayer.route.methods
      )) {
        const method = routeMethodsData[0] as ExpressMethodValues;
        const active = routeMethodsData[1] as unknown as boolean;
        if (active) {
          const pathMethodOperation: SwaggerOperationObject = {
            parameters: [],
          };
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
      // for (const key of keys) {
      //   // Replace the parameter at the specific offset
      //   const paramPattern = new RegExp(`:${key.name}(\\([^)]*\\))?`, 'g');
      //   swaggerPath = swaggerPath.replace(paramPattern, `{${key.name}}`);
      // }

      const match = expressLayer.regexp
        .toString()
        .match(/^\/\^\\\/(.*?)\\\/\?\(\?=\\\/|\$\)\/i$/);
      //   swaggerPath = swaggerPath.replace(paramPattern, `{${key.name}}`);
      processRouters(
        expressLayer.handle.stack,
        swaggerSetup,
        match ? `/${match[1]}` : null
      );
    } else if (
      expressLayer.name !== 'query' &&
      expressLayer.name !== 'expressInit'
    ) {
      console.log(`Middleware: ${expressLayer.name}`);
    }
  }
  return getRouter({ content: JSON.stringify(swaggerSetup) });
};

// Function to inspect Express app stack
export function inspectAppStack(app: { _router: ExpressRoute }) {
  const stack = app._router.stack;

  for (const layer of stack) {
    if (layer.route) {
      const route = layer.route as ExpressRoute;
      console.log(
        `Route: ${Object.keys(route.methods).join(',')} ${route.path}`
      );
      layer.route.stack.forEach((routeLayer) => {
        console.log(`  ${routeLayer.method.toUpperCase()} ${route.path}`);
      });
    } else if (layer.name === 'router' && layer.handle.stack) {
      console.log(`Router: ${layer.regexp}`);
      inspectRouterStack(layer.handle.stack);
    } else if (layer.name !== 'query' && layer.name !== 'expressInit') {
      console.log(`Middleware: ${layer.name}`);
    }
  }
}

function inspectRouterStack(stack: ExpressLayer[]) {
  for (const layer of stack) {
    if (layer.route) {
      const route = layer.route as ExpressRoute; // Type assertion
      // This is a route handler within the router
      console.log(
        `  Route: ${Object.keys(route.methods).join(',')} ${route.path}`
      );
      route.stack.forEach((routeLayer) => {
        console.log(`    ${routeLayer.method?.toUpperCase()} ${route.path}`);
      });
    } else if (layer.name === 'router' && layer.handle.stack) {
      // This is a nested router
      console.log(`  Nested Router: ${layer.regexp}`);
      inspectRouterStack(layer.handle.stack);
    } else {
      // This is middleware within the router
      console.log(`  Middleware: ${layer.name}`);
    }
  }
}

// inspectAppStack(app);
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const healthCheck: express.RequestHandler<void> = (_, res) => {
  res.status(200).json({ message: 'Hello World!' });
};

app.use('/health', healthCheck);

app.use('/swagger-ui', processRouters(app._router.stack));

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
