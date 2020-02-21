import unittest
import ../src/analytic
import sequtils
import sugar
import math

template assert_eq[T](a: T, b: T) =
    if a != b:
        raiseAssert("\n left: " & $a & "\nright: " & $b & "\n")

test "one":
    let t = @[0,  1,  2,  3,  4,  5 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40].map(x => x.float)
    let res = @[(1,4.0)].process(t, w)
    res.assert_eq @[(32.5, 2, 5)]

test "simple":
    let t = @[0,   1,  2,  3,  4, 5].map(x => x.float)
    let w = @[10, 20, 30, 20, 10, 5].map(x => x.float)
    let res = @[(1,2.0), (1,3.0)].process(t, w)
    res.assert_eq @[(25.0, 1, 2), (20.0, 2, 4)]


test "skip_time":
    let t = @[0,   1,  3,  4, 5].map(x => x.float)
    let w = @[10, 20, 20, 10, 5].map(x => x.float)
    var res = @[(1,2.0), (1,3.0)].process(t, w)
    res[1][0] = res[1][0].floor
    res.assert_eq @[(15.0, 0, 1), (13.0, 1, 3)]

test "overlap":
    let i1: Interval = (10.0, 0, 2)
    let i2: Interval = (10.0, 1, 3)
    let i3: Interval = (10.0, 3, 5)
    assert overlap(i1, i2) == true
    assert overlap(i2, i3) == false

test "find_best":
    let t = @[0,  1,  2,  3,  4,  5 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40].map(x => x.float)
    let res = @[(1,4.0), (2,2.0)].process(t, w)
    res.assert_eq @[(17.5, 0, 3), (35.0, 3, 4), (40.0, 4, 5)]

test "find_best_2":
    let t = @[0,  1,  2,  3,  4,  5 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40].map(x => x.float)
    let res = @[(1,4.0), (2,2.0)].process(t, w)
    res.assert_eq @[(17.5, 0, 3), (35.0, 3, 4), (40.0, 4, 5)]

test "find_best_fail":
    let t = @[0,  1,  2,  3,  4,  5 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40].map(x => x.float)
    let res = @[(1,4.0), (2,3.0)].process(t, w)
    let empty: seq[Interval] = @[]
    res.assert_eq empty
    