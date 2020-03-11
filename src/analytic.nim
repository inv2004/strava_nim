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
    #echo total
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

proc process_old*(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[Interval] =
    echo "processing ", pattern

    let best = pattern.generate_best(time, watts)
    pattern.select_all(best) 

proc process*(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[Interval] =
  echo "processing: ", pattern

  let n = watts.len
  var sums = @[0]
  var current_sum = 0
  for val in watts:
    current_sum += val.int + 1
    sums.add(current_sum)

  echo "DEBUG1: ",sums

  var template_list: seq[int] = @[]
  for val in pattern:
    for i in 1..val.repeat:
      template_list.add(val.duration.int)

  let m = template_list.len
  if m == 0:
    return @[]

  echo "DEBUG2: ",template_list

  var dyn_arr: seq[seq[int]] = @[]

  var first_arr: seq[int] = @[]
  let val = template_list[0]
  for i in 1..n:
    if i < val:
      first_arr.add(0)
      continue
    first_arr.add(sums[i] - sums[i-val])

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

  for x in dyn_arr:
    echo "DEBUG3: ",x

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

  echo "solution:   ", solution

  return solution

when isMainModule:
  let pattern = @[(1,4.0), (2,2.0)]
  let t = @[0,  1,  2,  3,  4,  5,  6,  7 ].map(x => x.float)
  let w = @[10, 10, 20, 30, 40, 40, 50, 60].map(x => x.float)
  echo pattern.process(t, w)

