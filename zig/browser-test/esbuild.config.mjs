import * as esbuild from 'esbuild';

const watch = process.argv.includes('--watch');

const commonOptions = {
  bundle: true,
  format: 'esm',
  target: 'es2022',
  sourcemap: true,
};

// Bundle SharedWorker coordinator
const coordinatorBuild = esbuild.build({
  ...commonOptions,
  entryPoints: ['src/coordinator/shared-worker.ts'],
  outfile: 'fixtures/coordinator.js',
});

// Bundle provider worker
const providerBuild = esbuild.build({
  ...commonOptions,
  entryPoints: ['src/provider/worker.ts'],
  outfile: 'fixtures/provider.js',
});

// Bundle main client library
const clientBuild = esbuild.build({
  ...commonOptions,
  entryPoints: ['src/index.ts'],
  outfile: 'fixtures/crsql-multitab.js',
});

if (watch) {
  const ctx = await esbuild.context({
    ...commonOptions,
    entryPoints: [
      'src/coordinator/shared-worker.ts',
      'src/provider/worker.ts',
      'src/index.ts',
    ],
    outdir: 'fixtures',
  });
  await ctx.watch();
  console.log('Watching for changes...');
} else {
  await Promise.all([coordinatorBuild, providerBuild, clientBuild]);
  console.log('Build complete');
}
