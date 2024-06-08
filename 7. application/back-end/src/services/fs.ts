import {
  readFile,
  writeFile,
  PathOrFileDescriptor,
  WriteFileOptions,
} from 'node:fs';
import { EventEmitter } from 'node:events';

export const readFileAsync = ({
  filePath,
  options = {},
}: {
  filePath: PathOrFileDescriptor;
  options?:
    | ({
        encoding?: null | undefined;
        flag?: string | undefined;
      } & EventEmitter.Abortable)
    | null
    | undefined;
}): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    readFile(filePath, options, (error, data) =>
      error ? reject(error) : resolve(data)
    );
  });

export const writeFileAsync = ({
  filePath,
  data,
  options = {},
}: {
  filePath: PathOrFileDescriptor;
  data: string | NodeJS.ArrayBufferView;
  options: WriteFileOptions;
}): Promise<void> =>
  new Promise((resolve, reject) => {
    writeFile(filePath, data, options, (error) =>
      error ? reject(error) : resolve()
    );
  });
