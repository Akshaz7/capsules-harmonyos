/**
 * Cactus on-device inference (Node-API). Model weights are NOT in the package: pass a
 * directory of Cactus v2 weights (with config.txt and components/manifest.json).
 * initModel and complete run on a worker thread and return Promises.
 */
export { initModel, complete, freeModel } from 'libcactus_napi.so';
