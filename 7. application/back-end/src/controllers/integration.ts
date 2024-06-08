import { Readable } from 'node:stream';

import HttpClient from '@dnorio/httpclient';
import { RequestHandler } from 'express';

const httpClient = HttpClient();

export const testHttp: RequestHandler = async (_req, res) => {
  const streamReturn = await httpClient.callHTTP({
    uri: 'https://jsonplaceholder.typicode.com/todos/1',
    stream: true,
    outputHeadersToHide: [
      'access-control-allow-credentials',
      'age',
      'alt-svc',
      'cache-control',
      'cf-cache-status',
      'cf-ray',
      'connection',
      'content-encoding',
      'content-type',
      'date',
      'etag',
      'expires',
      'nel',
      'pragma',
      'report-to',
      'reporting-endpoints',
      'server',
      'transfer-encoding',
      'vary',
      'via',
      'x-content-type-options',
      'x-powered-by',
      'x-ratelimit-limit',
      'x-ratelimit-remaining',
      'x-ratelimit-reset',
    ],
  });
  if (streamReturn.body) {
    Readable.fromWeb(streamReturn.body).pipe(res);
  } else {
    res.end();
  }
};
