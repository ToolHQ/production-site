import { dirname, resolve } from 'path';
import { fileURLToPath } from 'url';
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

export default {
  mode: 'development',
  target: 'node',
  entry: './src/app.ts',
  resolve: {
    fallback: {
      url: false
    }
  },
  experiments: {
    outputModule: true
  },
  output: {
    chunkFormat: 'module',
    clean: true,
    filename: 'bundle.js',
    library: {
      type: 'module'
    },
    path: resolve(__dirname, './dist'),
    publicPath: ''
  },
  devtool: 'inline-source-map',
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
    ],
  },
  resolve: {
    extensions: ['.ts', '.js'],
  },
};