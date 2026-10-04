import type React from 'react';
import type {BoardKey} from '../timeline';
import {Quiz} from './Quiz';
import {Converter} from './Converter';
import {Split} from './Split';
import {Pomodoro} from './Pomodoro';
import {Water} from './Water';
import {Tennis} from './Tennis';

export {POMODORO_RING} from './Pomodoro';
export {Quiz, Converter, Split, Pomodoro, Water, Tennis};

export const BOARDS: Record<BoardKey, React.FC<{f: number; tapAt?: number}>> = {
  quiz: Quiz,
  converter: Converter,
  split: Split,
  pomodoro: Pomodoro,
  water: Water,
  tennis: Tennis,
};
