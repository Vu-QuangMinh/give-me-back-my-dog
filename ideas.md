# Maps
Have something to let people know that it is getting late.
Get to the end of the combat map without killing all enemies will allow you to move out of that node but you only get reward if all enemies are killed.
Maybe have the characters comment about it. Calculate the percentage of passing, assume random choices. IF it is less than 70%, says we need to hurry up. If it is less than 50%, says that we are going to be late. If it is less than 30% says that we are doomed unless something great happen.
SHow this percentage out.



uhm xong r có boss kiểu immune damage của mình
nhưng trong phòng có trap
mình phải redirect mấy cái đó
đánh mới có dam

# Problem: if there are attacks that affect both players, how do we even time the dodge?

## Enemies:
1) Grunt (already have) = Skull crab
2) Archer (already have, nerf it down a bit) = Bat (sonic wave attac).
3) Assassin - Attack twice, move faster. Also 3HP = Squirrel
4) Bulldozer (tanky, charge attack, push even if blocked) (5HP)
5) Mage - Squishy, attacks are forecasted. 1 with AOE 2 aimin on the closest player. The other damage everything in a line also aim at a player
6) Guard: hold a shield, always try to FACE the closest character, get -1 damage if attacked from the direction it is facing +45 degree angle both side (total of 120* degree, will have a visual crescent of blue glow to show it). Will always try to move toward the closest player
HP:5
Move: 2
If projectile comes from the shielded angles, auto direct it to the nearest player, added negative_bounce = 0.5 normal negative bounce.
Attack 1: Melee, 1 hit, damage 0. Stun 1. This attack applies to all the tiles adjacent to the shield crescent
Attack 2: Melee, 3 hit, damage 1 each. Fast attack all of them 
7) Spider: Move 3, 1HP, explode when in melee range, 2 actions.
8) Feral beast: if you counter attack, he will attack you again. This keep on going until you miss a parry or if he dies. 5HP
## Miniboss

2) Summoner (7HP): Keep summoning random enemies.
3) High guard (10HP): Grunt + bulldozer + Assassin + Guard
4) Brood mother: Shoot out spider within 4 range of the characters. 2 a turn as a free action. Attack: spit web: Aim at the closest player, deal no damage but apply 1 slow (move 1 less). Effect: in AOE 2, apply the web effect (visual effect: has white webline lay on top of it). Spider movement on the webbed area does not cost movement point. The Brood mother try to move run away from players. Movement =1. If it has a player adjacent to it,  no longer spawn spiderling, no longer run away, no longer spit web. Attack: 1 damage + 1 poison (poison stack)
5) Arch mage: Squishy, attacks are forecasted. 1 with AOE 3 aimin on the closest player. The other damage everything in a line at 3 hex width. Teleport to the other side of the map if there is a player within 2 hexes.

# Terrains
## Types of overall terrains: 
Each arc will have 3 types of terrains with different composition, relating to the actual lore/ position of that place
For example: Arc 1 would be from the house to the mountain so any nodes within the first 33 km would be suburban or abandonned type. from 33.1 to 66.0km would be Forest / meadow type and from 66.1 to end would be mountain type. Would this be too many assets?

Type tiles need for Arc 1-1 (surburban)
- Road
- Tree
- House
- Traffic light, stop signs
- Trash can
- Bigger house with glass windows.

