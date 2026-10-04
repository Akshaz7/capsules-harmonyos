import React from 'react';
import {Composition} from 'remotion';
import {Trailer} from './Trailer';
import {DURATION, FPS, HEIGHT, WIDTH} from './timeline';

export const RemotionRoot: React.FC = () => (
  <Composition id="HarmoniserTrailer" component={Trailer} durationInFrames={DURATION} fps={FPS} width={WIDTH} height={HEIGHT} />
);
