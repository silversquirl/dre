# Deterministic regular expressions

A DRE (deterministic regular expression) is a regular expression with the additional restriction that each byte matched must immediately determine the path through the regex.
This means that a DRE directly represents a DFA (deterministic finite automaton), as compared to normal regular expressions which represent NFAs (nondeterministic finite automata).

## Examples

Here is a regular expression: `abc|a+`.
This is not a valid DRE, as the character `a` can be matched by both alternatives, but it can be losslessly transformed into the DRE `a(bc|a*)`.
Note how the leading `a` in each alternative is factored out, meaning the path through the regex can be determined immediately after reading each input character.

## Benefits

Matching engines for deterministic regex can be simultaneously very simple and extremely fast.
Because the path through a DRE is fully deterministic, there is no need to use backtracking (which is slow) or DFA minimization (which is complex).

Since DRE engines don't need backtracking, they always run in `O(n)` time, and are therefore not susceptible to the catastrophic backtracking issues that plague backtracking engines such as PCRE.
Because they generate DFAs directly rather than converting from NFAs, they avoid potentially hiding high memory usage - all the DFA states are visible in the expression itself, meaning a complex DFA will have a complex DRE to match.

Additionally, it's immediately clear to a user how a DRE works at the machine level.
There is no need to guess about the path taken through a DRE, because it's immediately evident in the expression itself.

## Status

This implementation is fairly complete, but is missing proper unicode support for character classes.
It has also not been heavily optimized, but should be fairly performant already.

## Usage

This implementation is usable through the Zig package manager:

```zig
// build.zig.zon
.dre = .{
    .url = "https://github.com/silversquirl/dre/archive/<COMMIT HASH GOES HERE>.tar.gz",
    .hash = "<SHA2 CHECKSUM GOES HERE>",
},
```

```zig
// build.zig
exe.addModule("dre", b.dependency("dre", .{}).module("dre"));
```

To match a string with a DRE, simply call `dre.match(regex, str)`. This function will return a struct containing the `len` of the match, as well as whatever `tag` was passed last (if any).

There is also a `dre.Lexer` API that can be used to easily create tokenizers using DRE.
See the test at the bottom of `src/lexer.zig` for an example usage.

(TODO: more API documentation)

## Syntax

The syntax for writing a DRE is similar to most other regex flavours, with a few notable differences:

- Special characters are escaped with `%` rather than the usual `\\`, to make writing DREs in string literals easier
- There are no capture groups. Instead, we have "tags", which are written as `<my_tag>`, `<another>`, etc.

Note that `.` is equivalent to `[^\r\n]`. To match any byte at all, use `[^]`.

(TODO: comprehensive syntax reference)
