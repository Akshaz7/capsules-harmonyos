/** Loads Cactus weights from an on-device directory. Resolves true on success. */
export const initModel: (path: string) => Promise<boolean>;
/**
 * Single-turn completion (temperature 0). Resolves to the raw Cactus response JSON string.
 * system: optional system message. maxTokens: defaults to 128.
 * toolsJson: optional tools array; enables force_tools (response.function_calls holds the call).
 */
export const complete: (prompt: string, system?: string, maxTokens?: number, toolsJson?: string) => Promise<string>;
/** Releases the loaded model. */
export const freeModel: () => void;
