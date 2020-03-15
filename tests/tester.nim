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

test "two":
    let t = @[0,  1,  2,  3,  4,  5 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40].map(x => x.float)
    let res = @[(2,2.0)].process(t, w)
    res.assert_eq @[(25.0, 2, 3), (40.0, 4, 5)]

test "simple":
    let t = @[0,   1,  2,  3,  4, 5].map(x => x.float)
    let w = @[10, 20, 30, 20, 10, 5].map(x => x.float)
    let res = @[(1,2.0), (1,3.0)].process(t, w)
    res.assert_eq @[(15.0, 0, 1), (20.0, 2, 4)]

test "skip_time":
    let t = @[0,   1,  3,  4, 5].map(x => x.float)
    let w = @[10, 20, 20, 10, 5].map(x => x.float)
    var res = @[(1,2.0), (1,3.0)].process(t, w)
    res[1][0] = res[1][0].floor
    res.assert_eq @[(15.0, 0, 1), (16.0, 2, 4)]

test "skip_time_2":
    let t = @[0,   1,  4,  4, 5].map(x => x.float)
    let w = @[10, 20, 20, 10, 5].map(x => x.float)
    var res = @[(1,2.0), (1,3.0)].process(t, w)
    res[1][0] = res[1][0].floor
    res.assert_eq @[(15.0, 0, 1), (11.0, 4, 6)]

test "overlap":
    let i1: Interval = (10.0, 0, 2)
    let i2: Interval = (10.0, 1, 3)
    let i3: Interval = (10.0, 3, 5)
    assert overlap(i1, i2) == true
    assert overlap(i2, i3) == false

test "find_best":
    let t = @[0,  1,  2,  3,  4,  5,  6,  7 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40, 50, 50].map(x => x.float)
    let res = @[(1,4.0), (2,2.0)].process(t, w)
    res.assert_eq @[(17.5, 0, 3), (40.0, 4, 5), (50.0, 6, 7)]

test "find_best_2":
    let t = @[0,  1,  2,  3,  4,  5,  6,  7 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40, 40, 40].map(x => x.float)
    let res = @[(1,4.0), (2,2.0)].process(t, w)
    res.assert_eq @[(17.5, 0, 3), (40.0, 4, 5), (40.0, 6, 7)]

test "find_best_fail":
    let t = @[0,  1,  2,  3,  4,  5,  6,  7 ].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40, 50, 50].map(x => x.float)
    let res = @[(1,4.0), (1,2.0), (1,3.0)].process(t, w)
    let empty: seq[Interval] = @[]
    res.assert_eq empty

test "format_result":
    var a: seq[Interval] = @[]
    a.add (avg: 176.7, start: 60*00+41, stop:60*20+40)
    a.add (avg: 305.0, start: 60*21+32, stop:60*24+31)
    a.add (avg: 306.6, start: 60*27+25, stop:60*30+24)
    a.add (avg: 285.6, start: 60*33+25, stop:60*36+24)
    a.add (avg: 195.0, start: 60*39+23, stop:60*42+22)
    a.add (avg: 241.2, start: 60*45+28, stop:60*48+27)
    a.add (avg: 254.9, start: 60*51+36, stop:60*54+35)
    a.add (avg: 224.4, start: 60*57+31, stop:60*60+30)
    let str = a.normalize_result()
    str.assert_eq "1x20(176) + 7x3(305 306 285 195 241 254 224)"
