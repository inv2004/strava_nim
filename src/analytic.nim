import times
import strformat
import sequtils
import algorithm
import re
import strutils
import sugar
import logging

type
    Interval* = tuple
        avg: float
        start: int
        stop: int

    Pattern* = tuple
        repeat: int
        duration: float

template trace(args: varargs[string, `$`]): untyped =
    when not defined(release):
        echo args.join()

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
    for x in plan.findAll(re"\d+x\d+[smh]?"):
        var str = x
        let m =
            if x.endsWith "s":
                str.removeSuffix "s"
                1
            elif x.endsWith "m":
                str.removeSuffix "m"
                60
            elif x.endsWith "h":
                str.removeSuffix "h"
                3600
            else:
                60
        let vals = str.split('x')
        let pattern: Pattern = (vals[0].parseInt, (m * vals[1].parseInt).float)
        result.add(pattern)

proc fmt_duration(x: float): string =
    let x = x.int
    if x mod 3600 == 0:
        result = $(x div 3600) & "h"
    if x mod 60 == 0:
        result = $(x div 60)
    else:
        result = ($x) & "s"

proc `$`*(found: seq[Interval]): string =
    var prev: (int, float, seq[int]) = (0, 0.0, @[])

    for x in found:
        if x.duration == prev[1]:
            prev[0].inc
            prev[2].add(x.avg.int)
        else:
            if prev[0] > 0:
                if result.len > 0:
                    result &= " + "
                let ints = prev[2].join(" ")
                result &= fmt "{prev[0]}x{prev[1].fmt_duration} ({ints})"
            prev = (1, x.duration, @[x.avg.int])

    if prev[0] > 0:
        if result.len > 0:
            result &= " + "
        let ints = prev[2].join(" ")
        result &= fmt "{prev[0]}x{prev[1].fmt_duration} ({ints})"

proc generate_best*(pattern: seq[Pattern], time: seq[float], watts: seq[
        float]): seq[seq[Interval]] =
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

func overlap*(a, b: Interval): bool =
    if a.start <= b.start and a.stop > b.start:
        return true
    if b.start <= a.start and b.stop > a.start:
        return true
    return false

proc select_all*(pattern: seq[Pattern], best: seq[seq[Interval]]): seq[Interval] =

    # let total = pattern.zip(best).mapIt(it[1].len ^ it[0].repeat).prod()
    # echo total
    var i = 0
    var m = 0.0
    var candidate = newSeq[Interval]()

    proc step(left: seq[Interval], acc: float, pattern: seq[Pattern], best: seq[
            seq[Interval]]) =
        if pattern.len == 0:
            if acc > m:
                m = acc
                candidate = left
        else:
            for x in best[0]:
                #if i mod 1_000_000 == 0:
                #    echo fmt"{(100 * i) / total:.10f}%"
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

proc process_old*(pattern: seq[Pattern], time: seq[float], watts: seq[
        float]): seq[Interval] =
    echo "processing ", pattern

    let best = pattern.generate_best(time, watts)
    pattern.select_all(best)

proc movingSum(time, watts: seq[float]): seq[int] =
    result.add(0)
    var current_sum = 0
    var prev = (-1.0, 0.0)

    for (t, val) in time.zip(watts):
        let t_diff = (t-prev[0]).int
        if t_diff > 2:
            for i in 0..t_diff-2:
                current_sum += 1
                result.add(current_sum)
        elif t_diff == 2:
            current_sum += int((prev[1] + val) / 2)
            result.add(current_sum)

        current_sum += val.int + 1
        result.add(current_sum)
        prev = (t, val)

    result.mapIt(it.int)

proc expandTemplate(pattern: seq[Pattern]): seq[int] =
    for val in pattern:
        for i in 1..val.repeat:
            result.add(val.duration.int)


proc process*(pattern: seq[Pattern], tw: seq[(string, seq[float], seq[float])]): (int, seq[Interval]) =
    trace "processing: " & $pattern

    if tw.len == 0:
        return (0, @[])

    var sums: seq[int] = @[]

    for (_, time, watts) in tw:
        sums.add movingSum(time, watts)

    let n = sums.len - 1

    let template_list = expandTemplate(pattern)
    let m = template_list.len
    if m == 0:
        return (0, @[])

    var dyn_arr: seq[seq[int]] = @[]

    for j, val in template_list:
        var next_arr: seq[int] = @[]
        var max_in_prev = 0

        for i in 1..n:
            if i < val:
                next_arr.add(0)
                continue
            if max_in_prev > 0 or j == 0:
                let last = sums[i] - sums[i-val]
                next_arr.add(max_in_prev + last)
            else:
                next_arr.add(0)
            if j > 0:
                let prev_arr = dyn_arr[j-1]
                if max_in_prev < prev_arr[i - val]:
                    max_in_prev = prev_arr[i - val]

        dyn_arr.add(next_arr)

    when not defined(release):
        # trace "TIME: ", time
        # trace "WATT: ", watts.mapIt(it.int)
        trace "SUMS: ", sums
        trace "TMPL: ", template_list
        for x in dyn_arr: trace "DYNN: @[", x.mapIt(fmt"{it:3}").join(", "), "]"

    var ret_val = 0
    var ret_pos = -1
    var ret_pos_y = -1
    for jj in countdown(m-1, 0):
        for i in 0..<n:
            let j = dyn_arr[jj][i]
            if j > ret_val:
                ret_val = j
                ret_pos = i
                ret_pos_y = jj

    if ret_val == 0:
        return (0, @[])

    var solution = newSeq[Interval](ret_pos_y + 1)
    var sum_all = ret_val
    var pos_y = ret_pos_y
    var pos_x = ret_pos

    while pos_y >= 0:
        if dyn_arr[pos_y][pos_x] == sum_all:
            let len_val = template_list[pos_y]
            let sum_val = sums[pos_x+1] - sums[pos_x+1-len_val]
            let avg = (sum_val - len_val).float / len_val.float
            let i: Interval = (avg, pos_x+1-len_val, pos_x)
            solution[pos_y] = i
            pos_x -= len_val
            pos_y -= 1
            sum_all -= sum_val
        else:
            pos_x = pos_x - 1

    for j in template_list:
        ret_val -= j

    when not defined(release):
        trace "SOLU: ", solution.mapIt(it[2])

    return (ret_val, solution)

when isMainModule:
    let pattern = @[(1, 4.0), (2, 2.0)]
    let t = @[0, 1, 2, 3, 4, 5, 6, 7].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40, 50, 60].map(x => x.float)
    echo pattern.process(t, w)

