import math

def to_turns(deg):
    return math.radians(deg) / math.pi / 2.0

def cordic_step(error, x, y, step_no):
    if step_no == -3:
        if error > .5:
            return error - 1.0, x, y
        else:
            return error, x, y

    if step_no == -2:
        if -.25 <= error < .25:
            return error, x, y
        elif error < 0:
            return error + .5, -x, -y
        else:
            return error - .5, -x, -y

    if step_no == -1:
        if -.25 <= error < .25:
            return error, x, y
        elif error < 0:
            return error + .25, -y, x
        else:
            return error - .25, y, -x
        
    d = 2.0 ** -step_no
    rot = math.atan(d) / 2. / math.pi

    if error >= 0:
        rot = -rot
        d = -d

    return error + rot, x - d * y, d * x + y

def cordic_scale(step_count):
    t = 1.0
    for i in range(step_count):
        t /= math.sqrt(1 + 2. ** (-2*i))
    return t

def cos_sin(turns, prec = 32):
    turns = turns % 1.0

    error = -turns
    
    x, y = 1., 0

    for i in range(-3, prec, 1):
        error, x, y = cordic_step(error, x, y, i)

    t = cordic_scale(prec)

    return x * t, y * t

for prec in range(15, 50):
    tol = 2.0 ** (-prec+1)
    for i in range(0, 360):
        x, y = cos_sin(to_turns(i), prec)
        xv, yv = math.cos(math.radians(i)), math.sin(math.radians(i))
        xerr = abs(x-xv)
        yerr = abs(y-yv)
        if xerr > tol or yerr > tol:
            print(prec, i, "deg", int(math.log2(xerr)) if xerr else None, int(math.log2(yerr)) if yerr else None)
