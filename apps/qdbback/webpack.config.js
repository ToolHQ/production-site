import path from 'path'
import HtmlWebpackPlugin from 'html-webpack-plugin'
import { CleanWebpackPlugin } from 'clean-webpack-plugin'
import MiniCssExtractPlugin from 'mini-css-extract-plugin'

import { __dirname } from './dir.js'

export default {
  mode: 'production',
  entry: {
    index: [
      path.resolve(__dirname, 'assets/monitor/index.js'),
    ],
    bundle_head: path.resolve(__dirname, 'assets/monitor/style.scss'),
  },
  output: {
    path: path.resolve(__dirname, 'dist/monitor'),
    publicPath: '/',
  },
  plugins: [
    new CleanWebpackPlugin(),
    new HtmlWebpackPlugin({
      template: path.resolve(__dirname, 'assets/monitor/index.html'),
      filename: path.resolve(__dirname, './dist/monitor/index.html'),
      chunks: ['index'],
    }),
    new MiniCssExtractPlugin({ filename: 'style.css' }),
  ],
  module: {
    rules: [
      {
        test: /\.s[ac]ss$/i,
        sideEffects: true,
        use: [
          MiniCssExtractPlugin.loader,
          // Translates CSS into CommonJS
          'css-loader',
          // Compiles Sass to CSS
          'sass-loader',
        ],
      },
    ],
  },
  devtool: false,
  optimization: {
    minimize: true,
    moduleIds: 'size',
    mangleExports: 'size',
    usedExports: true,
    minimizer: [
      '...',
    ],
  },
}
