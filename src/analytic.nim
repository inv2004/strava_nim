import times
import strformat
import sequtils
import algorithm
import re
import strutils
import math
import sugar

type
    Interval* = tuple
        avg: float
        start: int
        stop: int

    Pattern* = tuple
        repeat: int
        duration: float


func duration(a: Interval): float =
    (a.stop - a.start + 1).float

proc `$`*(a: Interval): string =
    let d1 = initDuration(seconds = a.start).toParts()
    let d2 = initDuration(seconds = a.stop).toParts()
    let d3 = initDuration(seconds = a.duration().int).toParts()
    fmt"(avg: {a.avg:0.1f}, start: {d1[Minutes]:02}:{d1[Seconds]:02}, duration: {d3[Minutes]:02}:{d3[Seconds]:02}, stop:{d2[Minutes]:02}:{d2[Seconds]:02})"

proc `$`*(d: times.Duration): string =
    let d = d.toParts()
    fmt"{d[Hours]}:{d[Minutes]:02}:{d[Seconds]:02}"

proc normalize_plan*(plan: string): seq[Pattern] =
    for x in plan.findAll(re"\d+x\d+"):
        let vals = x.split('x')
        let pattern: Pattern = (vals[0].parseInt, (60 * vals[1].parseInt).float)
        result.add(pattern)    

proc generate_best*(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[seq[Interval]] =
    for (repeat, ws) in pattern:
        result.add(@[])
        var acc = 0.0
        var i = 0
        for ii, (tt, x) in time.zip(watts):
            let t = tt.int
            while time[i].int <= t-ws.int:
                acc -= watts[i]
                i += 1
            acc += x
            if t+1 >= ws.int:
                let interval: Interval = (acc / ws, time[i].int, t)
                assert time[i].int <= t
                result[^1].add(interval)

    func cmp2(a, b: Interval): int =
        result = cmp(a.avg * a.duration, b.avg * b.duration)
        if result == 0:
            result = cmp(a.start, b.start)
            if result == 0:
                result = cmp(a.stop, b.stop)

    for x in result.mitems:
        x.sort(cmp2, Ascending)

func overlap*(a,b: Interval): bool =
    if a.start <= b.start and a.stop > b.start:
        return true
    if b.start <= a.start and b.stop > a.start:
        return true
    return false

proc select_top_1*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =
    result.add best[0][^1]

proc select_top_2*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =
    var m = 0.0

    for x in best[0]:
        for y in best[1]:
            if not(x.stop <= y.start):
                continue

            let work = x.avg*15*60 + y.avg*180
            if work > m:
                result = @[x,y]
                m = work

proc select_top_3*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =
    var m = 0.0

    echo "variants: ", best[0].len * (best[1].len ^ 2)

    for x in best[0]:
        for y in best[1]:
            if not(x.stop <= y.start):
                continue

            for z in best[1]:
                if not(y.stop <= z.start):
                    continue
        
                let work = x.avg*pattern[0].duration + y.avg*pattern[1].duration + z.avg*pattern[1].duration
                if work > m:
                    result = @[x,y,z]
                    m = work

proc select_all*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =

    let total = pattern.zip(best).mapIt(it[1].len ^ it[0].repeat).prod()
    echo total
    var i = 0
    var m = 0.0
    var candidate = newSeq[Interval]()

    proc step(left: seq[Interval], acc:float, pattern: seq[Pattern], best: seq[seq[Interval]]) =
        if pattern.len == 0:
            if acc > m:
                m = acc
                candidate = left
        else:
            for x in best[0]:
                if i mod 1_000_000 == 0:
                    echo fmt"{(100 * i) / total:.10f}%"
                i.inc()
                if left.len > 0 and not(left[^1].stop <= x.start):
                    continue
                let acc = acc + x.avg * x.duration
                if pattern[0].repeat == 1:
                    step(left & x, acc, pattern[1..pattern.high], best[1..best.high])
                else:
                    var newP = pattern
                    newP[0].repeat.dec()
                    step(left & x, acc, newP, best)

    step(@[], 0.0, pattern, best)
    return candidate
    
# when isMainModule:
#     let pattern = @[(1,4.0), (2,2.0)]
#     let t = @[0,  1,  2,  3,  4,  5 ].map(x => x.float)
#     let w = @[10, 10, 20, 30, 40, 40].map(x => x.float)
#     let best = pattern.generate_best(t, w)
#     echo pattern.select_all(best)

proc select_one(last:int, pattern: Pattern, best: seq[Interval]): seq[Interval] =
    var best = best
    var repeat = pattern.repeat

    while best.len > 0 and repeat > 0:
        let x = best.pop()
        if not(last <= x.start):
            continue
        if result.anyIt(overlap(it, x)):
            continue
        result.add(x)
        repeat -= 1

    if repeat > 0:
        echo "not all interval found"
        return @[]

proc select_top_33*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =
    let p1 = select_one(0, pattern[0], best[0])
    let p2 = select_one(p1[0].stop, pattern[1], best[1])
    echo p2


proc select_top*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =
    let count = pattern.map(x => x.repeat).sum()
    if count == 1:
        return pattern.select_top_1(best)
    elif count == 2:
        return pattern.select_top_2(best)
    elif count == 3:
        return pattern.select_top_3(best)

proc process*(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[Interval] =
    echo "processing ", pattern

    var best = pattern.generate_best(time, watts)
    for x in best.mitems:
        x = x[0..<1000]

    for x in best:
        echo x.len

    pattern.select_all(best) 


