import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import esbuild from 'rollup-plugin-esbuild';

export default {
  input: 'src/index.js',
  output: [
    {
      file: 'dist/index.js',
      format: 'cjs',
      sourcemap: true,
      exports: 'named',
    },
    {
      file: 'dist/index.esm.js',
      format: 'esm',
      sourcemap: true,
    },
  ],
  external: ['react', '@rails/actioncable'],
  plugins: [
    resolve({ extensions: ['.js', '.jsx'] }),
    commonjs(),
    esbuild({
      include: /\.[jt]sx?$/,
      exclude: /node_modules/,
      jsx: 'transform', // classic React.createElement — PresenceContext.jsx imports React
      target: 'es2020',
      sourceMap: true,
    }),
  ],
};
