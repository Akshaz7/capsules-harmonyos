/**
 * Design tokens for the redesign (light mode only). Shared by T3 (shell, screens, frame) and T6 (capsule
 * patterns). Ask T3 before changing a value here.
 */

export class Palette {
  static readonly blue: string = '#2F5BFF';
  static readonly bluePressed: string = '#1F45D6';
  static readonly orange: string = '#FF7A45';
  static readonly orangeIcon: string = '#E8692E';
  static readonly orangeText: string = '#A8411A';
  static readonly orangeTint: string = '#FFEDE4';
  static readonly orangeTintSoft: string = '#FFF3EC';
  static readonly hotChipBg: string = '#FFEFE6';
  static readonly text: string = '#1B2236';
  static readonly text2: string = '#5B6478';
  static readonly text3: string = '#3D4A66';
  static readonly disabled: string = '#9AA4BA';
  static readonly checkboxOff: string = '#8E99B2';
  static readonly bg: string = '#F2F4F9';
  static readonly surface: string = '#FFFFFF';
  static readonly card: string = '#F5F7FB';
  static readonly tint: string = '#EAF0FF';
  static readonly chip: string = '#EEF2FF';
  static readonly chipText: string = '#2A47C7';
  static readonly track: string = '#E4E9F3';
  static readonly line: string = '#E3E7F0';
  static readonly line2: string = '#E8ECF4';
  static readonly inputBorder: string = '#DCE2EE';
  static readonly softButton: string = '#F1F3F8';
  /** White at 94%. */
  static readonly frameBg: string = '#F0FFFFFF';
  /** Blue at 12%. */
  static readonly frameBorder: string = '#1F2F5BFF';
  /** text at 10%. */
  static readonly shadow: string = '#1A1B2236';
  /** The one page gradient: 360vp at the top, from this to bg. */
  static readonly gradientTop: string = '#DCE5FF';
  /** The send button when the prompt is empty. */
  static readonly sendDisabled: string = '#C9D1E1';
  /** Dashed "Add" button border (record list). */
  static readonly dashed: string = '#B9C4E4';
  /** Week grid: missed day border, and today's missed day border. */
  static readonly missed: string = '#D3DAE8';
  static readonly todayMissed: string = '#8EA5FF';
  /** White at 72% (host bar scan button) and 90% (tab bar). */
  static readonly white72: string = '#B8FFFFFF';
  static readonly white90: string = '#E6FFFFFF';
  // Polish (NEW_POLISH): a secondary accent and layered-surface tones. Additive only.
  /** Secondary accent: gradient end stops, featured tile, selected tab dot, Share/QR icons only. */
  static readonly indigo: string = '#6C4DFF';
  static readonly indigoTint: string = '#EFEBFF';
  /** Gradient end for the primary button. */
  static readonly blueDeep: string = '#1B3BD1';
  /** Blue at 20%: coloured shadows. */
  static readonly blueGlow: string = '#332F5BFF';
  /** Blue at 8%: card border. */
  static readonly hairline: string = '#142F5BFF';
  static readonly cardTintTop: string = '#F7F9FF';
  static readonly cardTintBottom: string = '#FFFFFF';
}

/** One text role: size in fp and font weight. */
export interface TextRole {
  size: number;
  weight: number;
}

export class Type {
  static readonly badge: TextRole = { size: 12, weight: 600 };
  static readonly caption: TextRole = { size: 13, weight: 500 };
  static readonly secondary: TextRole = { size: 14, weight: 600 };
  static readonly label: TextRole = { size: 15, weight: 600 };
  static readonly input: TextRole = { size: 16, weight: 600 };
  static readonly title: TextRole = { size: 17, weight: 700 };
  static readonly wordmark: TextRole = { size: 19, weight: 700 };
  static readonly section: TextRole = { size: 22, weight: 800 };
  static readonly question: TextRole = { size: 24, weight: 800 };
  static readonly pageTitle: TextRole = { size: 28, weight: 800 };
  /** Hero numbers: 48 to 76fp, weight 800, with tabular figures (TABULAR). */
  static readonly heroMin: number = 48;
  static readonly heroMax: number = 76;
  static readonly heroWeight: number = 800;
  /** fontFeature value for tabular figures. */
  static readonly TABULAR: string = '"tnum" on';
}

export class Radius {
  static readonly frame: number = 28;
  static readonly heroCard: number = 22;
  static readonly card: number = 18;
  static readonly cardLarge: number = 20;
  static readonly button: number = 16;
  static readonly buttonLarge: number = 18;
  static readonly input: number = 12;
  static readonly chip: number = 10;
  static readonly chipLarge: number = 14;
  static readonly iconTile: number = 13;
  static readonly pill: number = 22;
  static readonly checkbox: number = 8; // 26vp box; 7 for a 24vp box
  static readonly sheet: number = 28;
  static readonly tileCard: number = 22;
  static readonly pillLarge: number = 24;
  static readonly tile: number = 14;
  static readonly primaryButton: number = 20;
}

export class Space {
  static readonly frameTop: number = 4;
  static readonly frameSide: number = 12;
  static readonly frameBottom: number = 16;
  static readonly body: number = 16;
  static readonly block: number = 14;
  static readonly cards: number = 10;
  /** Minimum touch target; enlarge with responseRegion, not by changing the look. */
  static readonly touch: number = 44;
  /** The page gradient's height. */
  static readonly gradient: number = 360;
}

export class Effects {
  static readonly frameShadow: ShadowOptions = { radius: 40, offsetY: 18, color: Palette.shadow };
  static readonly softShadow: ShadowOptions = { radius: 24, offsetY: 8, color: Palette.shadow };
  static readonly frosted: BlurStyle = BlurStyle.Thin;
  static readonly cardShadow: ShadowOptions = { radius: 18, offsetX: 0, offsetY: 6, color: Palette.blueGlow };
  static readonly buttonShadow: ShadowOptions = { radius: 14, offsetX: 0, offsetY: 6, color: Palette.blueGlow };
  static readonly pressedScale: number = 0.97;
  static readonly pressMs: number = 120;
}
