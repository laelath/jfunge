# JFunge

JFunge is a Befunge to x86_64-linux compiler with support for `g` and `p`.

## Installation and Usage

To install, just clone the repository.
The output of the compiler is NASM-compatible assembly, and so requires NASM to create an executable from the output.
To compile a program, run the following commands:
```
racket -t jfunge.rkt -m foo.bf > foo.s
nasm -f elf64 foo.s
ld -o foo foo.o
```
Yes this is clunky, I will automate these steps at some point.

## Architecture

The compiler outputs an assembly program that is a 2D array of code 'cells' of a constant size.
During run time the cursor location is stored in `r15` as a pointer to the start of the current cell,
and the direction being stored in `r14` as an offset from the start of the current cell to the start of the next.
Then the direction changing instructions `<`, `>`, `^`, and `v` can be implemented as `mov`s to `r14`.
Then each cell can end with the 'ramp' instructions `mov r15, r14`, `jmp r15`,

The downside of this method is how to handle execution flowing out of bounds of the grid.
By the Befunge spec. Befunge programs actually exist in a torus, so execution needs to wrap around to the other side of the grid.
To implement this wrapping, 'fence' cells are placed around the perimeter of the grid that jump `r15` to the opposite side.

```
┌─╥─┬─╥─┬───┬───┬───┬───┐
│ ║ │ ║ │ ╔═╪═══╪═╗ │   │
│ ^ │ >═╪═# │ v │ -═╪═@ │
│   │   │   │   │   │   │
├───┼───┼───┼───┼───┼───┤
│   │   │   │   │   │   │
│ >═╪═v │   │ < │   │   │
│ ║ │ ║ │   │   │   │   │
└─╨─┴─╨─┴───┴───┴───┴───┘
```

From this design most instructions are implemented in a fairly straightforwards manner,
with the exception of a few 'fun' instructions: `"`, `#`, `g`, and `p`.

### \"

This instruction starts quote mode, a mode where each instruction instead pushes the ASCII value of its character until the another quote is reached.
To achieve this, each cell is prepended with a quote section that is a constant 10 bytes in length.
This section serves as an alternate entry point to the cell, making quote cells as simple as decrementing the cursor register to point to the quote entry.
For most cells this section is just a `push` instruction, followed by a few `nop`s and then a ramp.
The quote section of quote cells then just increments the cursor register to point to the regular entry point for the cell.

```
┌───────────────────┐
│       Quote       │ [4 Bytes]
│       Ramp        │ [6 Bytes]
├───────────────────┤
│                   │
│       Body        │ [<= 48 Bytes]
│                   │
│       Ramp        │ [6 Bytes]
└───────────────────┘
```

### \#

This instruction causes execution to 'bridge' over the next cell, resuming in the cell after that one depending on the direction.
One might think that this could be simply implemented as adding the direction offset to the cursor location an additional time,
but if the bridge cell is next to a fence, this would cause execution to jump the fence and start doing all kinds of unexpected things.

The program:
```
┌─┬─┬─┐
│>│v│ │
├─┼─┼─┤
│#│<│@│
└─┴─┴─┘
```
would exist in memory as:
```
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│t│t│t│t│c│l│>│v│ │r│l│#│<│@│r│c│b│b│b│b│
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
```
with `t` for top fence cells, `b` for bottom fence cells, `l` and `r` for left and right fence cells, and `c` for empty 'corner' fence cells.

Once execution gets to the bridge cell `#`, if it applies the direction twice, it will end up jumping to the right wall of the first row,
which will then send the cursor on to the start of the first row.
```
             ╔═════╗
┌─┬─┬─┬─┬─┬─┬⇓┬─┬─┬╨┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│t│t│t│t│c│l│>│v│ │r│l│#│<│@│r│c│b│b│b│b│
└─┴─┴─┴─┴─┴─┴─┴─┴─┴⇑┴─┴╥┴─┴─┴─┴─┴─┴─┴─┴─┘
                   ╚═══╝
```

Now if only there was some code that all cells but the fences had that adds the direction to the location and jumps...
Oh wait! The ramp for the quote block has exactly what we need!
Now we cant set the cursor location to the ramp since that would cause the ramp to jump to the next ramp rather than the body, making the bridge cell
bridge over all future cells, not just the next one.
Instead, we replace the normal ramp with `add r15, r14`, `mov rax, r15`, `sub rax, 6`, `jmp rax`.
Then the ramp of the next cell will again add `r14` to `r15`, still pointing to the body entry point, and jump there.

Now we get to a design decision.
Currently if there is a bridge next to the fence, the bridge will *not* cause the cell after the wrap-around to be skipped.

```
┌───┬───┬───┐
│   │   │   │
│ >═╪═v │   │
│   │ ║ │   │
├───┼─╫─┼───┤
╞═╗ │ ║ │ ╔═╡
│ #═╪═< │ @ │
│   │   │   │
└───┴───┴───┘
```

So this program halts rather than skipping over the `@` and looping forever.
The fence cells could be changed to skip the next cell after wrapping (and did initially),
but this was dropped to make behavior less dependent on the grid size.

### g

This instruction pops `y` and `x` off the stack and 'gets' the ascii value of an instruction from the grid at `(x,y)`.
The straightforwards way that this could be implemented would be to add a data table to the x64 program that contains the original character bytes.
However this is uncesseary.
Recall that we already have the character representation of each cell already for quote mode.
Instead of reading from a table, it reads the byte from the cell grid that occurs right after the `push` opcode in the quote section.
This has one fatal flaw; quote cells themselves have an add instruction there rather than a push one.
Fortunately for us, the instruction there has the high bit of the byte set, something that cannot happen in other cells because valid Befunge programs
are all ascii text, allowing a simple `test` with `0x80` to determine if the data we read should be replaced with `#\"`.

### p

This instruction pops `y`, `x`, and a character `c` off the stack, then 'puts' that instruction on the grid at `(x,y)`.
Despite the horrors of self-modifying code, with all the setup the implementation of `g` is not fairly straightforwards.

A table is added to the generated executable of all ascii cells that is indexed by `c`, and the data copied onto the cell grid, with the slight
wrinkle that this has to be done by a procedure outside the grid to prevent writing to memory that is currently being executed.

Oh wait... it's segfaulting?

Perhaps this isn't surprising to people, especially those familiar with operating systems, but the system is "helpfully" preventing us from
writing to the program by raising a segfault when we try to write to memory pages containing executable code,
assuming that any such writes must be erroneous or the result of an abuse of a security vulnerability.

The fix for this is thankfully simple. The setup instructions call `sys_mprotect` to enable writing to the memory pages in which the program grid reside.
This does add one final challenge of ensuring that the grid is aligned to the start of a memory page
(though this isn't strictly necessary as we could enable writing to the whole program).
To do this we take the admittedly hacky and not-fully-general route of telling NASM to align the start of the grid to 4KiB - the most common Linux page size.

## TODO
* Grid resizing on out-of-bounds writes (very hard)
* Decimal number I/O instructions (tedious)
* Shrink cell size for more compact programs
