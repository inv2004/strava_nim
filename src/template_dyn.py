import json

def find_max_template(times, watts, template):

    sums = [0]
    current_sum = 0

    prev_t = -1
    prev_w = 0

    for i in range(len(times)):
        t = times[i]
        w = watts[i]
        t_diff = t-prev_t
        if t_diff > 2:
            for i in range(1, t_diff):
                current_sum += 1
                sums.append(current_sum)
        elif t_diff == 2:
            current_sum += int((prev_w + w) / 2)
            sums.append(current_sum)

        current_sum += w + 1
        sums.append(current_sum)
        prev_t = t
        prev_w = w

    n = len(sums)-1
    # sums = [0]
    # current_sum = 0
    # for val in vector:
    #     current_sum += val+1
    #     sums.append(current_sum)

    template_list = []
    for val in template:
        d = val['duration']
        r = val['repeat']
        for i in range(r):
            template_list.append(d)

    m = len(template_list)
    if m == 0:
        return 0, []

    dyn_arr = []

    first_arr = []
    val = template_list[0]
    for i in range(n):
        if i+1 < val:
            first_arr.append(0)
            continue
        first_arr.append(sums[i+1]-sums[i+1-val])

    dyn_arr.append(first_arr)
    
    for j in range(1, m):
        prev_arr = dyn_arr[j-1]
        max_in_prev = 0
        next_arr = []
        val = template_list[j]
        for i in range(n):
            if i + 1 < val:
                next_arr.append(0)
                continue
            last = sums[i+1]-sums[i+1-val]
            if max_in_prev > 0:
                next_arr.append(max_in_prev + last)
            else:
                next_arr.append(0)
            if max_in_prev < prev_arr[i + 1 - val]:
                max_in_prev = prev_arr[i + 1 - val]
        dyn_arr.append(next_arr)

    ret_val = 0
    ret_pos = -1
    for i in range(n):
        j = dyn_arr[m-1][i]
        if j > ret_val:
            ret_val = j
            ret_pos = i

    if ret_val == 0:
        return ret_val, []

    solution = [None]*m
    sum_all = ret_val
    pos_y = m-1
    pos_x = ret_pos

    while pos_y >= 0:
        if dyn_arr[pos_y][pos_x] == sum_all:
            len_val = template_list[pos_y]
            sum_val = sums[pos_x+1] - sums[pos_x+1-len_val]
            avg = (sum_val - len_val) / len_val

            solution[pos_y] = {
                'avg': avg,
                'start': pos_x+1-len_val,
                'end': pos_x + 1,
            }
            pos_x -= len_val
            pos_y -= 1
            sum_all -= sum_val
        else:
            pos_x = pos_x - 1

    for j in template_list:
        ret_val -= j

    return ret_val, solution


# sums, dict = find_max_template([1, 3, 1], [{'repeat':1, 'duration': 1}])
# sums, dict = find_max_template([10, 11, 9, 5, 7], [{'repeat': 2, 'duration': 2}])

with open('2.json') as f:
    j = json.load(f)
    w = j[0]['data']
    t = j[1]['data']

sums, ints = find_max_template(t, w, [{'repeat':1, 'duration': 1200}, {'repeat':7, 'duration': 180}])

print(ints)

