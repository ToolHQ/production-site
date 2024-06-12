import express, {
  Request,
  Response,
  NextFunction,
  Router,
  RequestHandler,
} from 'express';

import Logger from '@dnorio/logger';
import { logRequestsConstructor } from '@dnorio/logger/requestLoggerMiddleware';
import { setReqIdMiddleware } from '@dnorio/logger/setId';
import { getRouter } from '@dnorio/swagger-router';

import { router as todoRoutes } from './routes/todo.js';
import integrationRoutes from './routes/integration.js';

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

type ExpressMethodValues =
  | 'get'
  | 'post'
  | 'put'
  | 'patch'
  | 'delete'
  | 'options'
  | 'head'
  | 'all';
type ExpressRoute = {
  methods: {
    [key in ExpressMethodValues]?: string;
  };
  path: string;
  stack: ExpressLayer[];
};
type ExpressLayer = {
  handle: RequestHandler;
  keys: { name: string; optional: boolean; offset: number }[];
  method?: ExpressMethodValues;
  name: string;
  params: undefined;
  path: undefined;
  regexp: RegExp;
  route?: ExpressRoute;
};

type OpenAPIObject = {
  openapi: string;
  info: SwaggerInfoObject;
  jsonSchemaDialect?: string;
  servers?: SwaggerServerObject[];
  paths: SwaggerPathsObject;
  webhooks?: {
    [key: string]: SwaggerPathItemObject | SwaggerReferenceObject;
  };
  components?: SwaggerComponentsObject;
  security?: SwaggerSecurityRequirementObject[];
  tags?: SwaggerTagObject[];
  externalDocs?: SwaggerExternalDocsObject;
};
type SwaggerInfoObject = {
  title: string;
  summary?: string;
  description?: string;
  termsOfService?: string;
  contact?: SwaggerContactObject;
  license?: SwaggerLicenseObject;
  version: string;
};
type SwaggerContactObject = {
  name?: string;
  url?: string;
  email?: string;
};
type SwaggerLicenseObject = {
  name: string;
  identifier?: string;
  url?: string;
};
type SwaggerServerObject = {
  url: string;
  description?: string;
  variables?: {
    [key: string]: SwaggerServerVariableObject;
  };
};
type SwaggerServerVariableObject = {
  enum?: string[];
  default: string;
  description?: string;
};
type SwaggerComponentsObject = {
  schemas?: { [key: string]: SwaggerSchemaObject };
  responses?: { [key: string]: SwaggerResponseObject | SwaggerReferenceObject };
  parameters?: {
    [key: string]: SwaggerParameterObject | SwaggerReferenceObject;
  };
  examples?: { [key: string]: SwaggerExampleObject | SwaggerReferenceObject };
  requestBodies?: {
    [key: string]: SwaggerRequestBodyObject | SwaggerReferenceObject;
  };
  headers?: { [key: string]: SwaggerHeaderObject | SwaggerReferenceObject };
  securitySchemes?: {
    [key: string]: SwaggerSecuritySchemeObject | SwaggerReferenceObject;
  };
  links?: { [key: string]: SwaggerLinkObject | SwaggerReferenceObject };
  callbacks?: { [key: string]: SwaggerCallbackObject | SwaggerReferenceObject };
  pathItems?: { [key: string]: SwaggerPathItemObject | SwaggerReferenceObject };
};
type SwaggerPathsObject = {
  [key: string]: SwaggerPathItemObject;
};
type SwaggerValidOperations =
  | 'get'
  | 'put'
  | 'post'
  | 'delete'
  | 'options'
  | 'head'
  | 'patch'
  | 'trace';
type SwaggerPathItemObject = {
  $ref?: string;
  summary?: string;
  description?: string;
  get?: SwaggerOperationObject;
  put?: SwaggerOperationObject;
  post?: SwaggerOperationObject;
  delete?: SwaggerOperationObject;
  options?: SwaggerOperationObject;
  head?: SwaggerOperationObject;
  patch?: SwaggerOperationObject;
  trace?: SwaggerOperationObject;
  servers?: SwaggerServerObject[];
  parameters?: (SwaggerParameterObject | SwaggerReferenceObject)[];
};
type SwaggerOperationObject = {
  tags?: string[];
  summary?: string;
  description?: string;
  externalDocs?: SwaggerExternalDocsObject;
  operationId?: string;
  parameters?: (SwaggerParameterObject | SwaggerReferenceObject)[];
  requestBody?: SwaggerRequestBodyObject | SwaggerReferenceObject;
  responses?: SwaggerResponsesObject;
  callbacks?: { [key: string]: SwaggerCallbackObject | SwaggerReferenceObject };
  deprecated?: boolean;
  security?: SwaggerSecurityRequirementObject[];
  servers?: SwaggerServerObject[];
};
type SwaggerExternalDocsObject = {
  description?: string;
  url: string;
};
type SwaggerParameterObject = {
  name: string;
  in: 'query' | 'header' | 'path' | 'cookie';
  description?: string;
  required?: boolean;
  deprecated?: boolean;
  allowEmptyValue?: boolean;
  style?:
    | 'matrix'
    | 'label'
    | 'form'
    | 'simple'
    | 'spaceDelimited'
    | 'pipeDelimited'
    | 'deepObject';
  explode?: boolean;
  allowReserved?: boolean;
  schema?: SwaggerSchemaObject;
  example?: unknown;
  examples?: { [key: string]: SwaggerExampleObject | SwaggerReferenceObject };
  content?: {
    [key: string]: SwaggerMediaTypeObject | SwaggerReferenceObject;
  };
};
type SwaggerRequestBodyObject = {
  description?: string;
  content: {
    [key: string]: SwaggerMediaTypeObject;
  };
  required?: boolean;
};
type SwaggerMediaTypeObject = {
  schema?: SwaggerSchemaObject;
  example?: unknown;
  examples?: { [key: string]: SwaggerExampleObject | SwaggerReferenceObject };
  encoding?: {
    [key: string]: SwaggerEncodingObject;
  };
};
type SwaggerEncodingObject = {
  contentType?: string;
  headers?: {
    [key: string]: SwaggerHeaderObject | SwaggerReferenceObject;
  };
  style?:
    | 'matrix'
    | 'label'
    | 'form'
    | 'simple'
    | 'spaceDelimited'
    | 'pipeDelimited'
    | 'deepObject';
  explode?: boolean;
  allowReserved?: boolean;
};
type IANAHttpStatusCode =
  | 100
  | 101
  | 102
  | 103
  | 200
  | 201
  | 202
  | 203
  | 204
  | 205
  | 206
  | 207
  | 208
  | 226
  | 300
  | 301
  | 302
  | 303
  | 304
  | 305
  | 306
  | 307
  | 308
  | 400
  | 401
  | 402
  | 403
  | 404
  | 405
  | 406
  | 407
  | 408
  | 409
  | 410
  | 411
  | 412
  | 413
  | 414
  | 415
  | 416
  | 417
  | 418
  | 421
  | 422
  | 423
  | 424
  | 425
  | 426
  | 427
  | 428
  | 429
  | 430
  | 431
  | 451
  | 500
  | 501
  | 502
  | 503
  | 504
  | 505
  | 506
  | 507
  | 508
  | 509
  | 510
  | 511;
type SwaggerResponsesStatusCodes = {
  [status in IANAHttpStatusCode]?:
    | SwaggerResponseObject
    | SwaggerReferenceObject;
};
type SwaggerResponsesObject = Partial<SwaggerResponsesStatusCodes> & {
  default?: SwaggerResponseObject | SwaggerReferenceObject;
};
type SwaggerResponseObject = {
  description: string;
  headers: { [key: string]: SwaggerHeaderObject | SwaggerReferenceObject };
  content: { [key: string]: SwaggerMediaTypeObject };
  links: { [key: string]: SwaggerLinkObject | SwaggerReferenceObject };
};
type SwaggerCallbackObject = {
  [expression: string]: SwaggerPathItemObject | SwaggerReferenceObject;
};
type SwaggerExampleObject = {
  summary?: string;
  description?: string;
  value?: unknown;
  externalValue?: string;
};
type SwaggerLinkObject = {
  operationRef?: string;
  operationId?: string;
  parameters?: { [key: string]: unknown };
  requestBody?: unknown;
  description?: string;
  server?: SwaggerServerObject;
};
type SwaggerHeaderObject = {
  description?: string;
  required?: boolean;
  deprecated?: boolean;
  allowEmptyValue?: boolean;
  style?:
    | 'matrix'
    | 'label'
    | 'form'
    | 'simple'
    | 'spaceDelimited'
    | 'pipeDelimited'
    | 'deepObject';
  explode?: boolean;
  allowReserved?: boolean;
  schema?: SwaggerSchemaObject;
  example?: unknown;
  examples?: { [key: string]: SwaggerExampleObject | SwaggerReferenceObject };
  content?: {
    [key: string]: SwaggerMediaTypeObject | SwaggerReferenceObject;
  };
};
type SwaggerTagObject = {
  name: string;
  description?: string;
  externalDocs?: SwaggerExternalDocsObject;
};
type SwaggerReferenceObject = {
  $ref: string;
  summary?: string;
  description?: string;
};
type SwaggerSchemaObject = {
  discriminator?: SwaggerDiscriminatorObject;
  xml?: SwaggerXMLObject;
  externalDocs?: SwaggerExternalDocsObject;
  example?: unknown;
};
type SwaggerDiscriminatorObject = {
  propertyName: string;
  mapping?: { [key: string]: string };
};
type SwaggerXMLObject = {
  name?: string;
  namespace?: string;
  prefix?: string;
  attribute?: boolean;
  wrapped?: boolean;
};
type IANAAuthenticationScheme =
  | 'Basic'
  | 'Bearer'
  | 'Digest'
  | 'DPoP'
  | 'GNAP'
  | 'HOBA'
  | 'Mutual'
  | 'Negotiate'
  | 'OAuth'
  | 'PrivateToken'
  | 'SCRAM-SHA-1'
  | 'SCRAM-SHA-256'
  | 'vapid';
type SwaggerSecuritySchemeObject =
  | {
      type: 'apiKey';
      description?: string;
      name: string;
      in: 'query' | 'header' | 'cookie';
    }
  | {
      type: 'http';
      description?: string;
      scheme: IANAAuthenticationScheme;
      bearerFormat?: string;
    }
  | {
      type: 'oauth2';
      description?: string;
      flows: SwaggerOAuthFlowsObject;
    }
  | {
      type: 'openIdConnect';
      description?: string;
      openIdConnectUrl: string;
    }
  | {
      type: 'mutualTLS';
      description?: string;
    };
type SwaggerOAuthFlowsObject = {
  implicit?: SwaggerOAuthFlowImplicitObject;
  password?: SwaggerOAuthFlowPasswordOrClientCredentialsObject;
  clientCredentials?: SwaggerOAuthFlowPasswordOrClientCredentialsObject;
  authorizationCode?: SwaggerOAuthFlowAuthorizationCodeObject;
};
type SwaggerOAuthFlowImplicitObject = {
  authorizationUrl: string;
  refreshUrl?: string;
  scopes: { [key: string]: string };
};
type SwaggerOAuthFlowPasswordOrClientCredentialsObject = {
  tokenUrl: string;
  refreshUrl?: string;
  scopes: { [key: string]: string };
};
type SwaggerOAuthFlowAuthorizationCodeObject = {
  authorizationUrl: string;
  tokenUrl: string;
  refreshUrl?: string;
  scopes: { [key: string]: string };
};
type SwaggerSecurityRequirementObject = {
  [key: string]: string[];
};

const processRouters = (
  routers: (Omit<Router, 'stack'> & { stack: ExpressLayer[] })[]
) => {
  const initialSwaggerSetup: OpenAPIObject = {
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
  };

  for (const router of routers) {
    for (const expressLayer of router.stack) {
      if (expressLayer.route) {
        let swaggerPath = expressLayer.route.path;
        const keys = expressLayer.keys;
        keys.sort((a, b) => b.offset - a.offset);
        for (const key of keys) {
          // Replace the parameter at the specific offset
          const paramPattern = new RegExp(`:${key.name}(\\([^)]*\\))?`, 'g');
          swaggerPath = swaggerPath.replace(paramPattern, `{${key.name}}`);
        }
        if (!initialSwaggerSetup.paths[swaggerPath]) {
          initialSwaggerSetup.paths[swaggerPath] = {};
        }
        for (const [method, active] of Object.entries(
          expressLayer.route.methods
        )) {
          if (active) {
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            initialSwaggerSetup.paths[swaggerPath]![
              method as SwaggerValidOperations
            ] = {
              description: 'lorem ipsum',
            };
          }
        }
      }
    }
  }
  return getRouter({ content: JSON.stringify(initialSwaggerSetup) });
};
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const healthCheck: express.RequestHandler<void> = (_, res) => {
  res.status(200).json({ message: 'Hello World!' });
};

app.use('/health', healthCheck);

app.use('/swagger-ui', processRouters([integrationRoutes]));

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
