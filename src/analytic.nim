import times
import strformat
import sequtils
import algorithm
import re
import strutils

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

proc `$`(a: Interval): string =
    let tstr = fromUnix(a.start).format("mm:ss")
    let dstr = fromUnix(a.duration.int).format("mm:ss")
    fmt"(avg: {a.avg}, start: {tstr}, duration: {dstr})"

proc `$`(d: Duration): string =
    let d = d.toParts()
    fmt"{d[Hours]}:{d[Minutes]:02}:{d[Seconds]:02}"

proc normalize_plan*(plan: string): seq[Pattern] =
    for x in plan.findAll(re"\d+x\d+"):
        let vals = x.split('x')
        let pattern: Pattern = (vals[0].parseInt, (60 * vals[1].parseInt).float)
        result.add(pattern)    

proc generate_best*(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[Interval] =
    for (repeat, ws) in pattern:
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
                result.add(interval)

    func cmp2(a, b: Interval): int =
        result = cmp(a.avg, b.avg)
        if result == 0:
            result = cmp(a.start, b.start)
            if result == 0:
                result = cmp(a.stop, b.stop)

    result.sort(cmp2, Ascending)

proc select_top*(pattern: seq[Pattern], best: seq[Interval]): seq[Interval] =
    var best = best
    func overlap(a,b: Interval): bool =
        if a.start <= b.start and a.stop > b.start:
            return true
        if b.start <= a.start and b.stop > a.start:
            return true
        return false

    # var ps = pattern
    # while best.len > 0 and ps.len > 0:
    #     let x = best.pop()
    #     for p in ps.mitems:
    #         if x.duration >= p.duration:
    #             block checkBlock:
    #                 for y in result:
    #                     if overlap(x, y):
    #                         # echo "overlap ", x, y
    #                         break checkBlock
    #                 result.add(x)
    #                 p[0] -= 1
    #     ps.keepItIf(it[0] > 0)
    #     echo $ps

    for (p, res) in pattern.zip(best):
        var repeat = p.repeat
        let ws = p.duration
        while best.len > 0 and repeat > 0:
            let x = best.pop()
            if x.duration >= ws:
                if result.allIt(not overlap(x, it)):
                    result.add(x)
                    repeat -= 1

    func cmp3(a, b: Interval): int =
        result = cmp(a.start, b.start)
        if result == 0:
            result = cmp(a.avg, b.avg)
            if result == 0:
                result = cmp(a.stop, b.stop)

    result.sort(cmp3, Ascending)

proc process*(pattern: seq[Pattern], time: seq[float], watts: seq[float]) =
    echo "processing ", pattern

    let best = pattern.generate_best(time, watts)
    let found = pattern.select_top(best) 

    for x in found:
        echo x
    