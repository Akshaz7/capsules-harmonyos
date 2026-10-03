// Short beeps through the ES8311 codec and the on-board speaker when a timer ends.
#pragma once

void beep_init(void);
void beep_play(void);  // returns immediately; does nothing if the codec was not found
