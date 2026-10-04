import {BEAT_LAYOUT, PERSONAS, type Persona} from '../timeline';
import {typingDuration} from './motion';

/** Local (within-beat) cue frames for a persona beat. */
export const beatTimes = (p: Persona) => {
  const typeAt = BEAT_LAYOUT.typeStart;
  const typeDur = typingDuration(p.prompt);
  const sendAt = typeAt + typeDur + BEAT_LAYOUT.sendHold;
  const boardAt = sendAt + BEAT_LAYOUT.flyFrames;
  const tapAt = BEAT_LAYOUT.tapDelay; // relative to boardAt
  return {typeAt, typeDur, sendAt, boardAt, tapAt};
};

/** Absolute cue frames for every persona (used by the sound mix). */
export const personaCues = () =>
  PERSONAS.map((p) => {
    const t = beatTimes(p);
    return {id: p.id, from: p.from, whip: p.transitionIn === 'whip', typeAt: p.from + t.typeAt, typeDur: t.typeDur, boardAt: p.from + t.boardAt};
  });
