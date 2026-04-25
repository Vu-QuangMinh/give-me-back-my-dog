1) Make sure that these values const PROJ_LAUNCH_SPEED    = 600.0  
const PROJ_DECAY_RATE      = 0.85 
const PROJ_NEGATIVE_BOUNCE = 200.0 
Have can be affacted by modifers. SHould have CURRENT_PROJ_LAUNCH_SPEED, CURRENT_PROJ_DECAY_RATE AND CURRENT_NEGATIVE_BOUNCE THAT TAKES MODIFERS. FOR NOW IT IS ALL EQUAL TO THEIR CONST VALUE BUT THEY CAN BE AFFECTED LATER.
2) Mike attack ends everyone turn, which is wrong. Each character attack only ends their own turn. Player's turn end when both playable character's turn ends.
3) From player turn to enemy turns, there will be a slight delay of 0.5s 
