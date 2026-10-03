/**
 * Voice input: speech -> text on the device with the system speech recognizer (speechRecognizer,
 * @kit.CoreSpeechKit), offline (online: 1). The text then goes into the normal create flow like typed text.
 *
 * Huawei's docs list Mandarin (and English in a Chinese context) as the only language and the offline model as
 * the only model; VOICE_LANGUAGE is what the phone eval showed works best for English requests.
 *
 * Microphone use needs ohos.permission.MICROPHONE (user_grant): declared in module.json5 and requested at
 * runtime (abilityAccessCtrl requestPermissionsFromUser) before start(). Reading a PCM file (the eval) does not.
 *
 * Usage (UI):
 *   const voice = new VoiceInput();
 *   const text = await voice.start((partial: string) => { this.input = partial; }); // resolves on silence/stop
 *   voice.stop();   // user tapped the mic again: finish and resolve with what was heard
 *   voice.cancel(); // leave the screen
 */
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export const VOICE_PERMISSION: string = 'ohos.permission.MICROPHONE';
export const VOICE_UNAVAILABLE: string = 'Voice input is not available on this phone.';
export const VOICE_NOTHING_HEARD: string = 'Nothing was heard. Try again.';
export const VOICE_LANGUAGE: string = 'zh-CN';
/** Longest utterance, in ms (the engine's short mode allows 60 s). */
const MAX_AUDIO_MS: number = 20000;
/** 1280 bytes = 40 ms of 16 kHz mono 16-bit PCM; writeAudio only accepts 640 or 1280 bytes. */
const CHUNK_BYTES: number = 1280;

const UNITS: Record<string, number> = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
  'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19
};
const TENS: Record<string, number> = {
  'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90
};

/**
 * Recognizer output -> request text: Chinese punctuation to English, no trailing full stop, number words to digits
 * ("twenty five minutes" -> "25 minutes", "a hundred" -> "100"), "i" -> "I". The rules only read digits.
 */
export function cleanTranscript(raw: string): string {
  let t = raw.replace(/。/g, '. ').replace(/，/g, ', ').replace(/？/g, '? ').replace(/！/g, '! ')
    .replace(/：/g, ': ').replace(/\s+/g, ' ').trim();
  t = t.replace(/\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)[ -](one|two|three|four|five|six|seven|eight|nine)\b/gi,
    (m: string, tens: string, unit: string) => `${TENS[tens.toLowerCase()] + UNITS[unit.toLowerCase()]}`);
  t = t.replace(/\b(a|one) hundred\b/gi, '100');
  t = t.replace(/\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)\b/gi,
    (m: string) => `${UNITS[m.toLowerCase()] ?? TENS[m.toLowerCase()]}`);
  t = t.replace(/\bi\b/g, 'I').replace(/[.!]+$/, '').trim();
  return t.length > 0 ? t.charAt(0).toUpperCase() + t.substring(1) : t;
}

interface Session {
  id: string;
  finals: string[];
  partial: string;
  resolve: (text: string) => void;
  reject: (e: Error) => void;
  onPartial?: (text: string) => void;
  timer: number;
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

/** Speech -> text with the system recognizer. One recognition at a time. */
export class VoiceInput {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private session: Session | null = null;
  private language: string;

  constructor(language?: string) {
    this.language = language ?? VOICE_LANGUAGE;
  }

  private async ensureEngine(): Promise<speechRecognizer.SpeechRecognitionEngine> {
    if (this.engine !== null) {
      return this.engine;
    }
    const extra: Record<string, Object> = { 'locate': 'CN', 'recognizerMode': 'short' };
    const params: speechRecognizer.CreateEngineParams = { language: this.language, online: 1, extraParams: extra };
    let engine: speechRecognizer.SpeechRecognitionEngine;
    try {
      engine = await speechRecognizer.createEngine(params);
    } catch (e) {
      throw new Error(VOICE_UNAVAILABLE);
    }
    const listener: speechRecognizer.RecognitionListener = {
      onStart: (sessionId: string, eventMessage: string) => {
      },
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {
      },
      onResult: (sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        const s = this.session;
        if (s === null || s.id !== sessionId) {
          return;
        }
        if (result.isFinal) {
          s.finals.push(result.result);
          s.partial = '';
        } else {
          s.partial = result.result;
        }
        s.onPartial?.(s.finals.concat(s.partial.length > 0 ? [s.partial] : []).join(' ').trim());
        if (result.isLast) {
          this.settle(sessionId, null);
        }
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        this.settle(sessionId, null);
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        this.settle(sessionId, new Error(`${VOICE_UNAVAILABLE} (${errorCode})`));
      }
    };
    engine.setListener(listener);
    this.engine = engine;
    return engine;
  }

  private settle(sessionId: string, error: Error | null): void {
    const s = this.session;
    if (s === null || s.id !== sessionId) {
      return;
    }
    this.session = null;
    clearTimeout(s.timer);
    const text = cleanTranscript(s.finals.concat(s.partial.length > 0 ? [s.partial] : []).join(' '));
    if (text.length > 0) {
      s.resolve(text); // a late error after text was heard still returns the text
    } else {
      s.reject(error ?? new Error(VOICE_NOTHING_HEARD));
    }
  }

  private begin(engine: speechRecognizer.SpeechRecognitionEngine, mode: number,
    onPartial?: (text: string) => void): Promise<string> {
    if (this.session !== null) {
      this.cancel();
    }
    const id = util.generateRandomUUID(false);
    const done = new Promise<string>((resolve, reject) => {
      const timer = setTimeout(() => this.stop(), MAX_AUDIO_MS + 5000);
      this.session = { id: id, finals: [], partial: '', resolve: resolve, reject: reject, onPartial: onPartial, timer: timer };
    });
    const audio: speechRecognizer.AudioInfo = { audioType: 'pcm', sampleRate: 16000, soundChannel: 1, sampleBit: 16 };
    const extra: Record<string, Object> = {
      'recognitionMode': mode, 'vadBegin': 2000, 'vadEnd': 3000, 'maxAudioDuration': MAX_AUDIO_MS
    };
    try {
      engine.startListening({ sessionId: id, audioInfo: audio, extraParams: extra });
    } catch (e) {
      this.settle(id, new Error(VOICE_UNAVAILABLE));
    }
    return done;
  }

  /**
   * Listens on the microphone (needs VOICE_PERMISSION granted) until the speaker stops (3 s of silence),
   * stop() or 20 s. Resolves with the recognised text; rejects with VOICE_NOTHING_HEARD or VOICE_UNAVAILABLE.
   * onPartial gets the running text while the user speaks.
   */
  async start(onPartial?: (text: string) => void): Promise<string> {
    const engine = await this.ensureEngine();
    return this.begin(engine, 0, onPartial);
  }

  /** Stops listening; start() resolves with what was heard so far. */
  stop(): void {
    const s = this.session;
    if (s !== null && this.engine !== null) {
      try {
        this.engine.finish(s.id);
      } catch (e) {
        this.settle(s.id, null);
      }
    }
  }

  /** Abandons the current recognition; start() rejects. */
  cancel(): void {
    const s = this.session;
    if (s !== null) {
      try {
        this.engine?.cancel(s.id);
      } catch (e) {
        // already finished
      }
      this.session = null;
      clearTimeout(s.timer);
      s.reject(new Error(VOICE_NOTHING_HEARD));
    }
  }

  /** Recognises a 16 kHz mono 16-bit PCM file (no microphone; for evals). */
  async transcribePcm(path: string): Promise<string> {
    const engine = await this.ensureEngine();
    const done = this.begin(engine, 1);
    const id = this.session?.id ?? '';
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(CHUNK_BYTES);
      let n = fileIo.readSync(file.fd, buf);
      while (n === CHUNK_BYTES && this.session !== null) {
        engine.writeAudio(id, new Uint8Array(buf.slice(0)));
        await sleep(40); // real time, as a microphone would deliver it
        n = fileIo.readSync(file.fd, buf);
      }
      for (let i = 0; i < 25 && this.session !== null; i++) { // 1 s of silence so the end is detected
        engine.writeAudio(id, new Uint8Array(CHUNK_BYTES));
        await sleep(40);
      }
    } finally {
      fileIo.closeSync(file);
    }
    this.stop();
    return done;
  }

  /** Languages the engine reports, e.g. ["zh-CN"]. */
  async languages(): Promise<string[]> {
    const engine = await this.ensureEngine();
    return engine.listLanguages({ sessionId: util.generateRandomUUID(false) });
  }

  /** Releases the engine. */
  shutdown(): void {
    this.cancel();
    this.engine?.shutdown();
    this.engine = null;
  }
}

/**
 * Headless voice eval (debug builds only): runs if <entry files>/speech-eval/run exists (pushed with
 * hdc file send -b by scripts/phone-speech-eval.sh). Recognises every speech-eval/*.pcm with each language in
 * speech-eval/languages.txt (default VOICE_LANGUAGE) and writes speech-eval/results.jsonl(.done).
 */
export async function runSpeechEvalIfRequested(context: common.Context): Promise<void> {
  const dir = `${context.filesDir}/speech-eval`;
  try {
    if (!fileIo.accessSync(`${dir}/run`)) {
      return;
    }
    fileIo.unlinkSync(`${dir}/run`);
  } catch (e) {
    return;
  }
  try {
    fileIo.unlinkSync(`${dir}/results.jsonl.done`);
  } catch (e) {
    // no marker from an earlier run
  }
  const out = fileIo.openSync(`${dir}/results.jsonl`,
    fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
  const write = (line: string): void => {
    fileIo.writeSync(out.fd, `${line}\n`);
  };
  try {
    let langs: string[] = [VOICE_LANGUAGE];
    try {
      langs = fileIo.readTextSync(`${dir}/languages.txt`).split(/\s+/).filter((l: string) => l.length > 0);
    } catch (e) {
      // default language only
    }
    const files = fileIo.listFileSync(dir).filter((n: string) => n.endsWith('.pcm')).sort();
    for (const lang of langs) {
      const voice = new VoiceInput(lang);
      let reported: string[] = [];
      try {
        reported = await voice.languages();
      } catch (e) {
        write(JSON.stringify({ language: lang, engine_error: e instanceof Error ? e.message : String(e) }));
        continue;
      }
      write(JSON.stringify({ language: lang, languages: reported }));
      for (const name of files) {
        const t0 = Date.now();
        let text = '';
        let error = '';
        try {
          text = await voice.transcribePcm(`${dir}/${name}`);
        } catch (e) {
          error = e instanceof Error ? e.message : String(e);
        }
        write(JSON.stringify({ language: lang, file: name, ms: Date.now() - t0, text: text, error: error }));
      }
      voice.shutdown();
    }
  } catch (e) {
    write(JSON.stringify({ eval_error: e instanceof Error ? e.message : String(e) }));
  } finally {
    fileIo.closeSync(out);
    fileIo.closeSync(fileIo.openSync(`${dir}/results.jsonl.done`, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY));
  }
}
