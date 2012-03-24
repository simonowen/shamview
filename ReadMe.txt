SAM HAM viewer for SAM Coupe (v1.0)
-----------------------------------

This package contains an image conversion script (shamconv.py) and native
SAM Coupé viewer program (shamview.asm).


Image Conversion
----------------

Usage: shamconv.py [-h] [-b B] [-s] image

  -h, --help  show this help message and exit
  -b B        set border colour entry (default=0)
  -s          save best/final images as PNG

Source images are automatically scaled to fit the SAM display size (256x192).

The conversion script requires Python and the Python Imaging Library (PIL).
ActivePython 2.7 is recommended for Windows users.  The PIL module may need to
be installed separately if 'import Image' fails when the script is run:  

  Windows x86: http://effbot.org/downloads/
  Windows x64: http://www.lfd.uci.edu/~gohlke/pythonlibs/   
  Linux: install the 'python-imaging' package 
  Mac: using MacPorts may be the easiest option for PIL 

Be sure to install the PIL version matching your Python release. 


Viewer
------

Modify the sample paths at the end of shamview.asm to add your own .sham files
then assemble by typing 'make'.  You'll need pyz80.py (http://pyz80.sf.net) to
be somewhere in your path.

There should be space for around 16 full-size images.  If the display is blank
you've probably overwritten DOS during loading, so try removing some images.


To-Do
-----

Improve dynamic colour selection using proper colour quantisation, rather than
just picking the most common colours.


---

Version 1.0 (2012/03/24)
- Initial release

---

Simon Owen
http://simonowen.com/sam/shamview/
