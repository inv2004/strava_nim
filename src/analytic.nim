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

proc fmt_duration(x: float): string =
    let x = x.int
    if x mod 3600 == 0:
        result = $(x div 3600) & "h"
    if x mod 60 == 0:
        result = $(x div 60)
    else:
        result = ($x) & "s"


proc normalize_result*(found: seq[Interval]): string =
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
                result &= fmt "{prev[0]}x{prev[1].fmt_duration}({ints})"
            prev = (1, x.duration, @[x.avg.int])

    if prev[0] > 0:
        if result.len > 0:
            result &= " + "
        let ints = prev[2].join(" ")
        result &= fmt "{prev[0]}x{prev[1].fmt_duration}({ints})"

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

proc process*(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[Interval] =
    debug "processing: " & $pattern

#   echo "time: ", time
#   echo "watt: ", watts

    var sums = @[0]
    var current_sum = 0

    var prev_t = -1.0
    var prev_val = 0.0

    for (t, val) in time.zip(watts):
        let t_diff = (t-prev_t).int
        if t_diff > 2:
            for i in countup(1, t_diff-1):
                current_sum += 1
                sums.add(current_sum)
        elif t_diff == 2:
            current_sum += int((prev_val + val) / 2)
            sums.add(current_sum)

        current_sum += val.int + 1
        sums.add(current_sum)
        prev_t = t
        prev_val = val

    let n = sums.len - 1

    var template_list: seq[int] = @[]
    for val in pattern:
        for i in 1..val.repeat:
            template_list.add(val.duration.int)

    let m = template_list.len
    if m == 0:
        return @[]

    var dyn_arr: seq[seq[int]] = @[]

    var first_arr: seq[int] = @[]
    let val = template_list[0]
    for i in 1..n:
        if i < val:
            first_arr.add(0)
            continue
        first_arr.add(sums[i] - sums[i-val])

    #echo "SUMS: ", sums
    #echo "TMPL: ", template_list
    #echo "FRST: ", first_arr

    dyn_arr.add(first_arr)

    for j in 1..<m:
        let prev_arr: seq[int] = dyn_arr[j-1]
        var max_in_prev = 0
        var next_arr: seq[int] = @[]
        let val = template_list[j]

        for i in 0..<n:
            if i + 1 < val:
                next_arr.add(0)
                continue
            let last = sums[i+1] - sums[i+1-val]
            if max_in_prev > 0:
                next_arr.add(max_in_prev + last)
            else:
                next_arr.add(0)
            if max_in_prev < prev_arr[i + 1 - val]:
                max_in_prev = prev_arr[i + 1 - val]
        dyn_arr.add(next_arr)

    var ret_val = 0
    var ret_pos = -1
    for i in 0..<n:
        let j = dyn_arr[m-1][i]
        if j > ret_val:
            ret_val = j
            ret_pos = i

    if ret_val == 0:
        return @[]

    var solution = newSeq[Interval](m)
    var sum_all = ret_val
    var pos_y = m - 1
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

#   echo "solution:   ", solution

    return solution

when isMainModule:
    let pattern = @[(1, 4.0), (2, 2.0)]
    let t = @[0, 1, 2, 3, 4, 5, 6, 7].map(x => x.float)
    let w = @[10, 10, 20, 30, 40, 40, 50, 60].map(x => x.float)
    echo pattern.process(t, w)

