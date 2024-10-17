Reimplementation of GNU coreutils in Zig.

Zig Coreutilz Project
=====================

Why?
----
The primary impetus for this project is simply to have a series of small Zig
projects I can learn from.  It would be nice if these tools get to a place of
being able to be used as a drop-in replacement of the GNU coreutils, but this
is neither likely, nor a goal of this project.

What Commands Are Supported?
----------------------------
The following commands have been implemented to some useful degree.

> seq

More To-Do
==========
Aside from all the commands which have not been implemented, there are some
missing details in those commands which have been partially implemented.

seq Command
-----------
 * support `-f,--format` options
 * use multiplication instead of repeated addition to avoid float drift

References
==========
 * [GNU lib progname.c][1]
 * [GNU coreutils seq.c][2]

##### Links

[1]: <https://github.com/coreutils/gnulib/blob/master/lib/progname.c> "progname.c"

[2]: <https://github.com/coreutils/coreutils/blob/master/src/seq.c> "seq.c"
