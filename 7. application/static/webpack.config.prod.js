const path = require('path');
const { CleanWebpackPlugin } = require('clean-webpack-plugin');
const WebpackObfuscator = require('webpack-obfuscator');

module.exports = {
  mode: 'production',
  entry: './src/app.ts',
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'dist'),
    publicPath: '',
  },
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
  plugins: [
    new CleanWebpackPlugin(),
    new WebpackObfuscator({
      // debugProtection: true,
      rotateStringArray: true,
      identifierNamesGenerator: 'mangled-shuffled', // Obfuscate class names
      stringArray: true, // Obfuscate strings
      stringArrayThreshold: 1, // Percent of strings that will be moved to a string array
      stringArrayEncoding: [
        'base64',
        'rc4'
      ]
    }, [])
  ]
};