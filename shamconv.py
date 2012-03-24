#!/usr/bin/env python

import os, sys
import struct
import argparse
import Image     # requires Python Imaging Library (PIL)

parser = argparse.ArgumentParser(description="Convert image to SAM HAM format (.sham)")
parser.add_argument('-b', action='store', type=int, help="set border colour entry (default=0)")
parser.add_argument('-s', default=False, action='store_true', help="save best/final images as PNG")
parser.add_argument('image', action='store')
args = parser.parse_args()


def pad_palette (list, entries):
    return list + list[:3] * ((entries*3 - len(list)) / 3)

def make_palette (list):
    p = []
    for i in list:
        p += sampal[i*3:i*3+3]
    return pad_palette(p, 256)

def uniquified (seq):
    seen = set()
    return [ x for x in seq if x not in seen and not seen.add(x) ]


# Intensity levels for the 3-bit SAM colour components
levels = [ 0x00, 0x24, 0x49, 0x6d, 0x92, 0xb6, 0xdb, 0xff];

sampal = [];

for i in range(128):
    red   = levels[ (i & 2)       | ((i & 0x20) >> 3) | ((i & 8) >> 3)]
    green = levels[((i & 4) >> 1) | ((i & 0x40) >> 4) | ((i & 8) >> 3)]
    blue  = levels[((i & 1) << 1) | ((i & 0x10) >> 2) | ((i & 8) >> 3)]
    sampal += (red, green, blue)

sampal = pad_palette(sampal, 256)
impal = Image.new("P", (1,1))
impal.putpalette(sampal)

file = args.image
try:
    im = Image.open(file).convert("RGB")
except IOError as e:
    sys.exit(e)

w, h = im.size
print "Image:", file, " Dimensions: %dx%d" % (w,h)

# Does the image need shrinking to fit?
if w > 256 or h > 192:
    # Resize image to fit, preserving the aspect ratio
    im.thumbnail((256,192), Image.ANTIALIAS)
    w, h = im.size
    print "Scaled source down to %dx%d" % (w,h)

# Ensure an even width so the pixel data is byte-aligned
if w&1:
    w &= ~1
    im = im.crop((0, 0, w, h))

# Use the basename of the input file for output filenames
base = os.path.splitext(file)[0]
#base = 'new' ###

# Perform the best-case conversion to the SAM palette
im128 = im.quantize(palette=impal)
if args.s:
    im128.save(base + "_128.png")

# Determine the top 16 colours in the best-cast image
top16 = map(lambda x: x[1], sorted(im128.getcolors(), reverse=True)[:16])

# 6 dynamic colours, with extras for each 32 pixels under full width (max=11)
ndcols = 6 + (256-w)/32 if w >= 96 else 11

# The static colours are the most common global colours
scols = top16[:16-ndcols]
print "%d dynamic colours, %d static:" % (ndcols, len(scols)), scols
scols += scols[:1] * (16-ndcols-len(scols))

# Default border color is the first entry, which is the most common colour
# This can be overridden with -b but must be in the static colour range
border = 0 if not args.b else args.b
if border < 0 or border >= len(scols):
    sys.exit("error: border colour must be in static range (0-%d)" % (len(scols)-1))

matched = 0
pix, dcols = [], []

# Create a working canvas used to build the output image
imham = Image.new("RGB", im.size)

# Process each line
for y in range(h):
    # Crop box for the line in the source image
    line = [0, y, w, y+1]

    # Sort the colours used on this line, with the most common first
    imline = im128.crop(line)
    lcols = map(lambda x: x[1], sorted(imline.getcolors(), reverse=True))

    # Build the line palette from the static colours and as many extra
    # line colours, taking care to avoid duplicates
    cols = uniquified(scols + lcols)[:16]
    cols += cols[:1] * (16 - len(cols))

    # Create a map to preserve matched colours, with others set to 255
    colset = set(cols)
    newpal = map(lambda x: (x if x in colset else 255), range(256))

    # Create a mask from the map, used to select non-matched line pixels
    immask = imline.point(newpal)
    immask = Image.eval(immask, lambda x: 127 if x==255 else 0).convert("1")
    matched += immask.getcolors()[0][0]

    # Re-convert the line image using the line-specific palette
    # This provides nearest alternatives for non-matched pixels
    imline = imline.convert("RGB")
    impal.putpalette(make_palette(cols))
    imline16 = imline.quantize(palette=impal).crop((0,0,w,1))

    # Paste the alternative pixels using the mask
    imline.paste(imline16, immask)
    imham.paste(imline, line)

    # Re-convert the new line (lossless) to get a palettised image
    imline = imline.quantize(palette=impal)

    # Save the line pixel data, combining nibbles to give SAM pixels
    data = list(imline.getdata())
    pix += [((p[0]<<4)|p[1]) for p in zip(data[::2], data[1::2])]

    # Save the line palette data, in normal order for now
    dcols.append(cols[-ndcols:])

if args.s:
    # If a border colour was specified, include it in the output image
    if args.b != None:
        border_rgb = tuple(sampal[scols[border]*3:scols[border]*3+3])
        imscreen = Image.new("RGB", (16+256+16, 24+192+24), border_rgb)
        imscreen.paste(imham, (16+(256-w)/2, 24+(192-h)/2))
        imham = imscreen

    # Save as palettised PNG to reduce file size
    impal.putpalette(sampal)
    imham = imham.quantize(palette=impal)
    imham.save(base + "_ham.png")

print "%d%% best-case conversion," % ((100.0*matched)/(w*h)),
print "using %d SAM colours" % len(imham.getcolors())

# Write the final SHAM file
fd = open(base + '.sham', 'wb')
fd.write(struct.pack('2s6B', 'SH', 0, ndcols, border, w/2, h, 0))
fd.write(bytearray(pix))
fd.write(bytearray(list(reversed(scols + dcols[0]))))
fd.write(bytearray([x for y in dcols[1:] for x in reversed(y)]))
fd.write(struct.pack('2s', "AM"))
fd.close()
