import React from 'react';
import {AbsoluteFill, staticFile} from 'remotion';
import {Video} from '@remotion/media';
import manifest from '../generated/footage-manifest.json';
import type {FootageKey} from '../timeline';
import {Placeholder} from './common';

const FOOTAGE = manifest as Record<string, string>;

export const hasFootage = (key: FootageKey) => Boolean(FOOTAGE[key]);

/** A screen recording cropped and scaled into the phone screen. Muted; the mix carries the sound. */
export const FootageVideo: React.FC<{name: FootageKey; trimBefore?: number}> = ({name, trimBefore}) => {
  const src = FOOTAGE[name];
  if (!src) return <Placeholder name={`${name}.mp4`} />;
  return (
    <AbsoluteFill>
      <Video src={staticFile(src)} muted objectFit="cover" trimBefore={trimBefore} style={{width: '100%', height: '100%'}} />
    </AbsoluteFill>
  );
};

/** Recording if present, else the given fallback (a board), else a placeholder. */
export const FootageOr: React.FC<{name: FootageKey; fallback?: React.ReactNode}> = ({name, fallback}) => {
  if (hasFootage(name)) return <FootageVideo name={name} />;
  if (fallback) return <>{fallback}</>;
  return <Placeholder name={`${name}.mp4`} />;
};
