import colorsys

for i, angle in enumerate(range(0, 360, 360/24)):                                            print "      p_colors(%d) => (%d, %d, %d)," % tuple([i] + [int(x * 255) for x in colorsys.hsv_to_rgb(angle/360., 1, 1)])
