/**
 * Build stages reported while generateCapsule works (T4-25), for the app's build animation (T3-28).
 * A stage carries only its name and, for 'cloud', the provider: never the request text or keys.
 */
export type BuildStageName = 'cache' | 'rules' | 'template' | 'marketplace' | 'on-device' | 'cloud' | 'validating' |
  'retrying' | 'done' | 'failed';

export interface BuildStage {
  name: BuildStageName;
  /** 'cloud' only: the provider asked ('anthropic', 'openai', 'mistral'). */
  provider?: string;
}

/** Called synchronously at each stage. It should be quick; whatever it throws is swallowed. */
export type StageListener = (stage: BuildStage) => void;

/** Reports a stage to the listener, if any. Never throws into the pipeline. */
export function emitStage(listener: StageListener | undefined, name: BuildStageName, provider?: string): void {
  if (listener === undefined) {
    return;
  }
  const stage: BuildStage = provider !== undefined ? { name: name, provider: provider } : { name: name };
  try {
    listener(stage);
  } catch (e) {
    // the build UI must never break the build
  }
}
