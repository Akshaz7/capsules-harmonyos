import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {SCENES} from './timeline';
import {AudioMix} from './components/AudioMix';
import {Scene1Problem} from './scenes/Scene1Problem';
import {Scene2Pain} from './scenes/Scene2Pain';
import {Scene3Turn} from './scenes/Scene3Turn';
import {Scene4People} from './scenes/Scene4People';
import {Scene5Home} from './scenes/Scene5Home';
import {Scene6Native} from './scenes/Scene6Native';
import {Scene7End} from './scenes/Scene7End';

const SCENE_COMPONENTS: [keyof typeof SCENES, React.FC][] = [
  ['problem', Scene1Problem],
  ['pain', Scene2Pain],
  ['turn', Scene3Turn],
  ['people', Scene4People],
  ['home', Scene5Home],
  ['native', Scene6Native],
  ['end', Scene7End],
];

export const Trailer: React.FC = () => (
  <AbsoluteFill style={{background: '#F2F4F9'}}>
    {SCENE_COMPONENTS.map(([key, C]) => (
      <Sequence key={key} name={key} from={SCENES[key].from} durationInFrames={SCENES[key].to - SCENES[key].from}>
        <C />
      </Sequence>
    ))}
    <AudioMix />
  </AbsoluteFill>
);
