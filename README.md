# chip8-assembler
An assembler for the CHIP-8, written in lua

## Syntax
- Instruction syntax is mostly the same as [Cowgod's reference](http://devernay.free.fr/hacks/chip8/C8TECH10.HTM), but with a few differences:
  - Bnnn (jump to address plus V0) is now:  
    `JP nnn + V0`  
    or  
    `JP V0 + nnn`  

  - Fx0A (wait for key press) is now:  
    `KEY Vx`

  - Fx29 (set I to location of hex digit in Vx) is now:  
    `HEX Vx`

  - Fx33 (store BCD of Vx in memory locations I, I+1, and I+2) is now:  
    `BCD Vx`

- Hex numbers are prefixed with `$`

- Trailing spaces don't matter

- Define symbols with:  
  `symbolName = number`

- Define labels with:  
  `label:`

- Comments are after semicolons on a single line

- The following directives are available:
  - `.byte n, ...`  
    Inserts each number argument as a byte.

  - `.spriteImage file`  
    Inserts a binary sprite based on an image file.  
    The image must be in monochrome, its width no more than 8, and its height no more than 15.  
	**Note!!!** This currently requires you run the file with [LÖVE](https://love2d.org/).

- Define macros with:
  `#define name value`  
  Macros are not the same as symbols, they can be any value as opposed to just numbers.

- Symbols and labels can be used before they're declared.  
  You can use them anywhere you can use a number.
