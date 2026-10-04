import React from 'react';
import {AbsoluteFill, Sequence} from 'remotion';
import {PersonaBeat, personaProps} from '../components/PersonaBeat';
import {PERSONAS, SCENES} from '../timeline';

export const Scene4People: React.FC = () => (
  <AbsoluteFill>
    {PERSONAS.map((p, i) => (
      <Sequence key={p.id} from={p.from - SCENES.people.from} durationInFrames={p.durationInFrames} name={p.id}>
        <PersonaBeat {...personaProps(p, PERSONAS[i + 1])} />
      </Sequence>
    ))}
  </AbsoluteFill>
);
