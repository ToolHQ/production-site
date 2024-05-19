import path, { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sync as glob } from 'glob';
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export default {
  mode: 'production',
  target: 'node',
  entry: () => {
    const entries = {};
    const files = glob('./src/**/*.ts');
    files.forEach(file => {
      const name = path.relative('./src', file).replace('.ts', '');
      console.log(name, file)
      entries[name] = `./${file}`;
    });
    return entries;
  },
  optimization: {
    removeEmptyChunks: true,
    usedExports: true,
    mergeDuplicateChunks: true,
    providedExports: true,
  },
  output: {
    chunkFormat: 'module',
    path: path.resolve(__dirname, 'dist'),
    filename: '[name].js',
    library: {
      type: 'module'
    },
  },
  experiments: {
    outputModule: true,
  },
  resolve: {
    extensions: ['.ts', '.js'],
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
    ],
  },
};
